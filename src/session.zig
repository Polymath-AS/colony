const std = @import("std");
const workspace = @import("workspace.zig");
const pty_mod = @import("pty.zig");
const log = @import("log.zig").scoped(.session);

pub const SessionId = extern struct {
    bytes: [16]u8,

    pub fn generate() SessionId {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        return .{ .bytes = bytes };
    }

    pub fn toString(self: SessionId) [32]u8 {
        return std.fmt.bytesToHex(self.bytes, .lower);
    }

    pub fn eql(self: SessionId, other: SessionId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

pub const SessionState = enum(u8) {
    created = 0,
    running = 1,
    suspended = 2,
    terminated = 3,
};

pub const TerminalSize = extern struct {
    cols: u16,
    rows: u16,
};

pub const GhosttyHandle = extern struct {
    ptr: ?*anyopaque = null,

    pub fn isValid(self: GhosttyHandle) bool {
        return self.ptr != null;
    }
};

pub const Session = struct {
    id: SessionId,
    workspace_id: workspace.WorkspaceId,
    state: SessionState,
    cwd: ?[]const u8,
    shell: ?[]const u8,
    title: ?[]const u8,
    size: TerminalSize,
    ghostty_handle: GhosttyHandle,
    exit_code: ?i32,
    created_at: i64,
    updated_at: i64,
    allocator: std.mem.Allocator,

    env: std.StringHashMap([]const u8),
    scrollback_lines: u32 = 10000,

    pty: ?*pty_mod.Pty = null,

    input_callback: ?*const fn (sess: *Session, data: []const u8) void = null,
    input_callback_ctx: ?*anyopaque = null,

    output_callback: ?*const fn (sess: *Session, data: []const u8) void = null,
    output_callback_ctx: ?*anyopaque = null,

    exit_callback: ?*const fn (sess: *Session, exit_code: i32) void = null,
    exit_callback_ctx: ?*anyopaque = null,

    pub fn create(allocator: std.mem.Allocator, ws_id: workspace.WorkspaceId) !*Session {
        const sess = try allocator.create(Session);
        errdefer allocator.destroy(sess);

        const now = std.time.timestamp();
        sess.* = .{
            .id = SessionId.generate(),
            .workspace_id = ws_id,
            .state = .created,
            .cwd = null,
            .shell = null,
            .title = null,
            .size = .{ .cols = 80, .rows = 24 },
            .ghostty_handle = .{},
            .exit_code = null,
            .created_at = now,
            .updated_at = now,
            .allocator = allocator,
            .env = std.StringHashMap([]const u8).init(allocator),
        };

        return sess;
    }

    pub fn setShell(self: *Session, shell: []const u8) !void {
        if (self.shell) |old| self.allocator.free(old);
        self.shell = try self.allocator.dupe(u8, shell);
    }

    pub fn setCwd(self: *Session, cwd: []const u8) !void {
        if (self.cwd) |old| self.allocator.free(old);
        self.cwd = try self.allocator.dupe(u8, cwd);
    }

    pub fn setTitle(self: *Session, title: []const u8) !void {
        if (self.title) |old| self.allocator.free(old);
        self.title = try self.allocator.dupe(u8, title);
    }

    pub fn resize(self: *Session, cols: u16, rows: u16) void {
        self.size = .{ .cols = cols, .rows = rows };
        self.updated_at = std.time.timestamp();
        if (self.pty) |pty| {
            pty.resize(cols, rows);
        }
    }

    pub fn start(self: *Session) !void {
        if (self.state != .created) return error.InvalidSessionState;
        self.state = .running;
        self.updated_at = std.time.timestamp();
        log.info("session started id={s}", .{&self.id.toString()});
    }

    pub fn spawnShell(self: *Session) !void {
        if (self.state != .created and self.state != .running) {
            log.warn("cannot spawn shell in state={d}", .{@intFromEnum(self.state)});
            return error.InvalidSessionState;
        }
        if (self.pty != null) {
            log.warn("pty already spawned", .{});
            return error.AlreadySpawned;
        }

        const shell = self.shell orelse "/bin/zsh";
        log.info("spawning shell={s} cwd={s}", .{ shell, self.cwd orelse "(none)" });

        const pty = try pty_mod.Pty.open(self.allocator);
        errdefer pty.close();

        try pty.spawn(
            shell,
            self.cwd,
            &self.env,
            .{ .cols = self.size.cols, .rows = self.size.rows },
        );

        self.pty = pty;
        self.state = .running;
        self.updated_at = std.time.timestamp();

        log.info("shell spawned for session id={s}", .{&self.id.toString()});
    }

    pub fn pollOutput(self: *Session) !?[]const u8 {
        const pty = self.pty orelse return null;

        if (pty.waitExit()) |code| {
            log.info("shell exited code={d}", .{code});
            self.terminateWithCode(code);
            return null;
        }

        var buf: [4096]u8 = undefined;
        const n = try pty.read(&buf);
        if (n == 0) return null;

        if (self.output_callback) |cb| {
            cb(self, buf[0..n]);
        }

        return null;
    }

    pub fn getPtyFd(self: *Session) ?std.posix.fd_t {
        return if (self.pty) |p| p.getMasterFd() else null;
    }

    fn terminateWithCode(self: *Session, code: i32) void {
        self.state = .terminated;
        self.exit_code = code;
        self.updated_at = std.time.timestamp();

        if (self.pty) |pty| {
            pty.close();
            self.pty = null;
        }

        if (self.exit_callback) |cb| {
            cb(self, code);
        }

        log.info("session terminated id={s} code={d}", .{ &self.id.toString(), code });
    }

    pub fn suspend_(self: *Session) !void {
        if (self.state != .running) return error.InvalidSessionState;
        self.state = .suspended;
        self.updated_at = std.time.timestamp();
    }

    pub fn resume_(self: *Session) !void {
        if (self.state != .suspended) return error.InvalidSessionState;
        self.state = .running;
        self.updated_at = std.time.timestamp();
    }

    pub fn terminate(self: *Session, exit_code: i32) void {
        self.state = .terminated;
        self.exit_code = exit_code;
        self.updated_at = std.time.timestamp();
        self.ghostty_handle = .{};
    }

    pub fn setEnv(self: *Session, key: []const u8, value: []const u8) !void {
        const k = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(k);
        const v = try self.allocator.dupe(u8, value);
        try self.env.put(k, v);
    }

    pub fn bindGhostty(self: *Session, handle: GhosttyHandle) void {
        self.ghostty_handle = handle;
    }

    pub fn writeInput(self: *Session, data: []const u8) void {
        if (self.state != .running) return;

        if (self.pty) |pty| {
            _ = pty.write(data) catch |e| {
                log.err("write to pty failed: {}", .{e});
            };
        }

        if (self.input_callback) |cb| {
            cb(self, data);
        }
    }

    pub fn setInputCallback(
        self: *Session,
        callback: ?*const fn (sess: *Session, data: []const u8) void,
        ctx: ?*anyopaque,
    ) void {
        self.input_callback = callback;
        self.input_callback_ctx = ctx;
    }

    pub fn setOutputCallback(
        self: *Session,
        callback: ?*const fn (sess: *Session, data: []const u8) void,
        ctx: ?*anyopaque,
    ) void {
        self.output_callback = callback;
        self.output_callback_ctx = ctx;
    }

    pub fn setExitCallback(
        self: *Session,
        callback: ?*const fn (sess: *Session, exit_code: i32) void,
        ctx: ?*anyopaque,
    ) void {
        self.exit_callback = callback;
        self.exit_callback_ctx = ctx;
    }

    pub fn deinit(self: *Session) void {
        if (self.pty) |pty| {
            pty.close();
            self.pty = null;
        }

        if (self.cwd) |c| self.allocator.free(c);
        if (self.shell) |s| self.allocator.free(s);
        if (self.title) |t| self.allocator.free(t);

        var it = self.env.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();

        self.allocator.destroy(self);
    }
};

test "session lifecycle" {
    const allocator = std.testing.allocator;
    const ws_id = workspace.WorkspaceId.generate();

    const sess = try Session.create(allocator, ws_id);
    defer sess.deinit();

    try std.testing.expectEqual(SessionState.created, sess.state);

    try sess.start();
    try std.testing.expectEqual(SessionState.running, sess.state);

    try sess.suspend_();
    try std.testing.expectEqual(SessionState.suspended, sess.state);

    try sess.resume_();
    try std.testing.expectEqual(SessionState.running, sess.state);

    sess.terminate(0);
    try std.testing.expectEqual(SessionState.terminated, sess.state);
    try std.testing.expectEqual(@as(?i32, 0), sess.exit_code);
}

test "session env" {
    const allocator = std.testing.allocator;
    const ws_id = workspace.WorkspaceId.generate();

    const sess = try Session.create(allocator, ws_id);
    defer sess.deinit();

    try sess.setEnv("FOO", "bar");
    try sess.setEnv("BAZ", "qux");

    try std.testing.expectEqualStrings("bar", sess.env.get("FOO").?);
    try std.testing.expectEqualStrings("qux", sess.env.get("BAZ").?);
}

var test_callback_called: bool = false;

fn testInputCallback(_: *Session, _: []const u8) void {
    test_callback_called = true;
}

test "session input callback" {
    const allocator = std.testing.allocator;
    const ws_id = workspace.WorkspaceId.generate();

    const sess = try Session.create(allocator, ws_id);
    defer sess.deinit();

    test_callback_called = false;
    sess.setInputCallback(testInputCallback, null);
    try sess.start();
    sess.writeInput("test");

    try std.testing.expect(test_callback_called);
}
