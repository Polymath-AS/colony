const std = @import("std");
const build_config = @import("build_config");

pub const structs = @import("structs.zig");
pub const ipc = @import("ipc.zig");
pub const surface = @import("surface.zig");

pub const SurfaceId = structs.SurfaceId;
pub const SurfaceSize = structs.SurfaceSize;
pub const TerminalSize = structs.TerminalSize;
pub const ContentScale = structs.ContentScale;

pub const Surface = surface.Surface;
pub const SurfaceState = surface.SurfaceState;

pub const IpcServer = ipc.IpcServer;
pub const IpcClient = ipc.IpcClient;
pub const IpcError = ipc.IpcError;
pub const Message = ipc.Message;
pub const MessageType = ipc.MessageType;

pub const Runtime = switch (build_config.runtime) {
    .none => @import("none.zig").Runtime,
    .gtk => @import("gtk/gtk.zig").Runtime,
    .swift => @import("swift.zig").Runtime,
};

pub const RuntimeOptions = struct {
    allocator: std.mem.Allocator,
};

test {
    std.testing.refAllDecls(@This());
}
