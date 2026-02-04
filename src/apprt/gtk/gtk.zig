const std = @import("std");
const apprt = @import("../apprt.zig");

pub const Runtime = struct {
    pub fn init(_: apprt.RuntimeOptions) !Runtime {
        @compileError("GTK runtime not implemented. Use Swift runtime on macOS or contribute GTK support.");
    }

    pub fn deinit(_: *Runtime) void {
        unreachable;
    }

    pub fn run(_: *Runtime) !void {
        unreachable;
    }

    pub fn wakeup(_: *Runtime) void {
        unreachable;
    }
};
