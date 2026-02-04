const std = @import("std");
const workspace = @import("workspace.zig");

pub const RegistryEntry = struct {
    id: workspace.WorkspaceId,
    name: []const u8,
    path: []const u8,
    last_opened: i64,

    pub fn deinit(self: *RegistryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(RegistryEntry),
    workspaces: std.AutoHashMap(workspace.WorkspaceId, *workspace.Workspace),
    registry_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, config_dir: []const u8) !*Registry {
        const self = try allocator.create(Registry);
        errdefer allocator.destroy(self);

        const registry_path = try std.fs.path.join(allocator, &.{ config_dir, "workspaces.json" });

        self.* = .{
            .allocator = allocator,
            .entries = .{},
            .workspaces = std.AutoHashMap(workspace.WorkspaceId, *workspace.Workspace).init(allocator),
            .registry_path = registry_path,
        };

        return self;
    }

    pub fn deinit(self: *Registry) void {
        var ws_it = self.workspaces.valueIterator();
        while (ws_it.next()) |ws_ptr| {
            ws_ptr.*.deinit();
        }
        self.workspaces.deinit();

        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);

        self.allocator.free(self.registry_path);
        self.allocator.destroy(self);
    }

    pub fn load(self: *Registry) !void {
        const file = std.fs.cwd().openFile(self.registry_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = std.json.parseFromSlice(
            struct { workspaces: []const struct {
                id: []const u8,
                name: []const u8,
                path: []const u8,
                last_opened: i64,
            } },
            self.allocator,
            content,
            .{},
        ) catch return;
        defer parsed.deinit();

        for (parsed.value.workspaces) |ws| {
            const entry = RegistryEntry{
                .id = workspace.WorkspaceId.fromString(ws.id) catch continue,
                .name = try self.allocator.dupe(u8, ws.name),
                .path = try self.allocator.dupe(u8, ws.path),
                .last_opened = ws.last_opened,
            };
            try self.entries.append(self.allocator, entry);
        }
    }

    pub fn save(self: *Registry) !void {
        const dir = std.fs.path.dirname(self.registry_path) orelse ".";
        try std.fs.cwd().makePath(dir);

        const file = try std.fs.cwd().createFile(self.registry_path, .{});
        defer file.close();

        var buf: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        try writer.writeAll("{\"workspaces\":[");

        for (self.entries.items, 0..) |entry, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print(
                \\{{"id":"{s}","name":"{s}","path":"{s}","last_opened":{d}}}
            ,
                .{
                    entry.id.toString(),
                    entry.name,
                    entry.path,
                    entry.last_opened,
                },
            );
        }

        try writer.writeAll("]}");

        try file.writeAll(fbs.getWritten());
    }

    pub fn createWorkspace(self: *Registry, name: []const u8, path: []const u8) !*workspace.Workspace {
        const ws = try workspace.Workspace.create(self.allocator, name, path);
        errdefer ws.deinit();

        try self.workspaces.put(ws.id, ws);

        const entry = RegistryEntry{
            .id = ws.id,
            .name = try self.allocator.dupe(u8, name),
            .path = try self.allocator.dupe(u8, path),
            .last_opened = std.time.timestamp(),
        };
        try self.entries.append(self.allocator, entry);
        try self.save();

        return ws;
    }

    pub fn openWorkspace(self: *Registry, id: workspace.WorkspaceId) !*workspace.Workspace {
        if (self.workspaces.get(id)) |ws| {
            return ws;
        }

        for (self.entries.items) |*entry| {
            if (entry.id.eql(id)) {
                const ws = try workspace.Workspace.create(self.allocator, entry.name, entry.path);
                ws.id = id;
                try ws.open();
                try ws.restore();
                try self.workspaces.put(id, ws);

                entry.last_opened = std.time.timestamp();
                try self.save();

                return ws;
            }
        }

        return error.WorkspaceNotFound;
    }

    pub fn closeWorkspace(self: *Registry, id: workspace.WorkspaceId) void {
        if (self.workspaces.fetchRemove(id)) |kv| {
            kv.value.deinit();
        }
    }

    pub fn deleteWorkspace(self: *Registry, id: workspace.WorkspaceId) !void {
        self.closeWorkspace(id);

        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].id.eql(id)) {
                var entry = self.entries.orderedRemove(i);
                entry.deinit(self.allocator);
                break;
            }
            i += 1;
        }

        try self.save();
    }

    pub fn listWorkspaces(self: *Registry) []const RegistryEntry {
        return self.entries.items;
    }

    pub fn getWorkspace(self: *Registry, id: workspace.WorkspaceId) ?*workspace.Workspace {
        return self.workspaces.get(id);
    }
};

test "registry create and list" {
    const allocator = std.testing.allocator;

    const tmp_dir = "/tmp/colony_test_registry";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const reg = try Registry.init(allocator, tmp_dir);
    defer reg.deinit();

    const ws = try reg.createWorkspace("test-workspace", "/tmp/project");
    try std.testing.expectEqualStrings("test-workspace", ws.name);

    const entries = reg.listWorkspaces();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
}
