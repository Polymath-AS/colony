const std = @import("std");
const persistence = @import("persistence.zig");
const session_mod = @import("session.zig");

pub const WorkspaceId = extern struct {
    bytes: [16]u8,

    pub fn generate() WorkspaceId {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        return .{ .bytes = bytes };
    }

    pub fn fromString(s: []const u8) !WorkspaceId {
        if (s.len != 32) return error.InvalidWorkspaceId;
        var bytes: [16]u8 = undefined;
        _ = std.fmt.hexToBytes(&bytes, s) catch return error.InvalidWorkspaceId;
        return .{ .bytes = bytes };
    }

    pub fn toString(self: WorkspaceId) [32]u8 {
        return std.fmt.bytesToHex(self.bytes, .lower);
    }

    pub fn eql(self: WorkspaceId, other: WorkspaceId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

pub const WorkspaceConfig = struct {
    allocator: std.mem.Allocator,
    shell: ?[]const u8 = null,
    env: std.StringHashMap([]const u8),
    startup_commands: std.ArrayListUnmanaged([]const u8),
    default_cwd: ?[]const u8 = null,
    restore_sessions: bool = true,

    pub fn init(allocator: std.mem.Allocator) WorkspaceConfig {
        return .{
            .allocator = allocator,
            .env = std.StringHashMap([]const u8).init(allocator),
            .startup_commands = .{},
        };
    }

    pub fn deinit(self: *WorkspaceConfig) void {
        self.env.deinit();
        self.startup_commands.deinit(self.allocator);
    }
};

pub const Workspace = struct {
    id: WorkspaceId,
    name: []const u8,
    path: []const u8,
    config: WorkspaceConfig,
    sessions: std.ArrayListUnmanaged(*session_mod.Session),
    db: ?*persistence.WorkspaceDb = null,
    allocator: std.mem.Allocator,
    created_at: i64,
    updated_at: i64,

    pub fn create(allocator: std.mem.Allocator, name: []const u8, path: []const u8) !*Workspace {
        const ws = try allocator.create(Workspace);
        errdefer allocator.destroy(ws);

        const now = std.time.timestamp();
        ws.* = .{
            .id = WorkspaceId.generate(),
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .config = WorkspaceConfig.init(allocator),
            .sessions = .{},
            .allocator = allocator,
            .created_at = now,
            .updated_at = now,
        };

        return ws;
    }

    pub fn open(self: *Workspace) !void {
        if (self.db != null) return;

        const db_path = try std.fs.path.join(self.allocator, &.{ self.path, ".colony", "workspace.db" });
        defer self.allocator.free(db_path);

        try std.fs.cwd().makePath(std.fs.path.dirname(db_path) orelse ".");

        self.db = try persistence.WorkspaceDb.open(self.allocator, db_path);
        try self.db.?.migrate();
    }

    pub fn close(self: *Workspace) void {
        if (self.db) |db| {
            db.close();
            self.db = null;
        }
    }

    pub fn createSession(self: *Workspace) !*session_mod.Session {
        const sess = try session_mod.Session.create(self.allocator, self.id);
        errdefer sess.deinit();
        try self.sessions.append(self.allocator, sess);
        return sess;
    }

    pub fn getSession(self: *Workspace, id: session_mod.SessionId) ?*session_mod.Session {
        for (self.sessions.items) |sess| {
            if (sess.id.eql(id)) return sess;
        }
        return null;
    }

    pub fn removeSession(self: *Workspace, id: session_mod.SessionId) ?*session_mod.Session {
        for (self.sessions.items, 0..) |sess, i| {
            if (sess.id.eql(id)) {
                return self.sessions.orderedRemove(i);
            }
        }
        return null;
    }

    pub fn persistSession(self: *Workspace, sess: *session_mod.Session) !void {
        std.debug.assert(sess.workspace_id.eql(self.id));
        if (self.db) |db| {
            try db.saveSession(sess);
        }
    }

    pub fn persist(self: *Workspace) !void {
        if (self.db) |db| {
            try db.saveWorkspaceMeta(self);
        }
    }

    pub fn restore(self: *Workspace) !void {
        if (self.db) |db| {
            try db.loadWorkspaceMeta(self);
            if (self.config.restore_sessions) {
                try self.restoreSessions();
            }
        }
    }

    pub fn restoreSessions(self: *Workspace) !void {
        if (self.db) |db| {
            var loaded = try db.loadSessions(self.allocator, self.id);
            defer loaded.deinit(self.allocator);
            for (loaded.items) |sess| {
                try self.sessions.append(self.allocator, sess);
            }
        }
    }

    pub fn deleteSession(self: *Workspace, id: session_mod.SessionId) !void {
        if (self.removeSession(id)) |sess| {
            if (self.db) |db| {
                try db.deleteSession(id);
            }
            sess.deinit();
        }
    }

    pub fn deinit(self: *Workspace) void {
        self.close();
        for (self.sessions.items) |sess| {
            sess.deinit();
        }
        self.sessions.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.config.deinit();
        self.allocator.destroy(self);
    }
};

test "workspace create and id" {
    const allocator = std.testing.allocator;
    const ws = try Workspace.create(allocator, "test", "/tmp/test");
    defer ws.deinit();

    try std.testing.expect(ws.name.len > 0);
    try std.testing.expectEqualStrings("test", ws.name);

    const id_str = ws.id.toString();
    const parsed = try WorkspaceId.fromString(&id_str);
    try std.testing.expect(ws.id.eql(parsed));
}
