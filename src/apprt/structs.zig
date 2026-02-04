const std = @import("std");

pub const SurfaceId = extern struct {
    bytes: [16]u8,

    pub fn generate() SurfaceId {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        return .{ .bytes = bytes };
    }

    pub fn eql(self: SurfaceId, other: SurfaceId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

pub const SurfaceSize = extern struct {
    width: u32,
    height: u32,
};

pub const TerminalSize = extern struct {
    cols: u16,
    rows: u16,
};

pub const ContentScale = extern struct {
    x: f32 = 1.0,
    y: f32 = 1.0,
};
