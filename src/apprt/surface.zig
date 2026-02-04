const std = @import("std");
const structs = @import("structs.zig");

pub const SurfaceState = enum {
    uninitialized,
    ready,
    focused,
    destroyed,
};

pub const Surface = struct {
    id: structs.SurfaceId,
    size: structs.SurfaceSize,
    terminal_size: structs.TerminalSize,
    content_scale: structs.ContentScale,
    state: SurfaceState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Surface {
        const self = try allocator.create(Surface);
        self.* = .{
            .id = structs.SurfaceId.generate(),
            .size = .{ .width = 800, .height = 600 },
            .terminal_size = .{ .cols = 80, .rows = 24 },
            .content_scale = .{},
            .state = .uninitialized,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Surface) void {
        self.allocator.destroy(self);
    }

    pub fn resize(self: *Surface, width: u32, height: u32) void {
        self.size = .{ .width = width, .height = height };
    }

    pub fn setContentScale(self: *Surface, x: f32, y: f32) void {
        self.content_scale = .{ .x = x, .y = y };
    }

    pub fn focus(self: *Surface) void {
        self.state = .focused;
    }

    pub fn unfocus(self: *Surface) void {
        if (self.state == .focused) {
            self.state = .ready;
        }
    }

    pub fn destroy(self: *Surface) void {
        self.state = .destroyed;
    }
};

test "surface lifecycle" {
    const allocator = std.testing.allocator;
    const surf = try Surface.init(allocator);
    defer surf.deinit();

    try std.testing.expectEqual(SurfaceState.uninitialized, surf.state);

    surf.state = .ready;
    surf.focus();
    try std.testing.expectEqual(SurfaceState.focused, surf.state);

    surf.unfocus();
    try std.testing.expectEqual(SurfaceState.ready, surf.state);
}
