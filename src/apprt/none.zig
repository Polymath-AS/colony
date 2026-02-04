const std = @import("std");
const apprt = @import("apprt.zig");

pub const Runtime = struct {
    allocator: std.mem.Allocator,

    pub fn init(opts: apprt.RuntimeOptions) !Runtime {
        return .{
            .allocator = opts.allocator,
        };
    }

    pub fn deinit(_: *Runtime) void {}

    pub fn run(_: *Runtime) !void {}

    pub fn wakeup(_: *Runtime) void {}
};
