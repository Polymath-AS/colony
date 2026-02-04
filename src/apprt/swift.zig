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

pub const SwiftBridge = extern struct {
    ptr: ?*anyopaque = null,

    pub fn isValid(self: SwiftBridge) bool {
        return self.ptr != null;
    }
};

var swift_app_delegate: ?SwiftBridge = null;

export fn colony_swift_set_delegate(delegate: SwiftBridge) void {
    swift_app_delegate = delegate;
}

export fn colony_swift_get_delegate() SwiftBridge {
    return swift_app_delegate orelse .{};
}

export fn colony_swift_run() callconv(.c) c_int {
    return 0;
}
