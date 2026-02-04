const std = @import("std");
const build_config = @import("build_config");

pub const structs = @import("structs.zig");
pub const ipc = @import("ipc.zig");
pub const surface = @import("surface.zig");

pub const Runtime = switch (build_config.runtime) {
    .none => @import("none.zig").Runtime,
    .gtk => @import("gtk/gtk.zig").Runtime,
    .swift => @import("swift.zig").Runtime,
};

pub const RuntimeOptions = struct {
    allocator: std.mem.Allocator,
};
