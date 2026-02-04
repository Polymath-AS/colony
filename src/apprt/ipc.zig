const std = @import("std");

pub const MessageType = enum(u8) {
    ping = 0,
    pong = 1,
    new_window = 2,
    focus_window = 3,
    close_window = 4,
};

pub const Message = struct {
    msg_type: MessageType,
    payload: []const u8,
};

pub const IpcError = error{
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    InvalidMessage,
};

pub const IpcServer = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, socket_path: []const u8) !*IpcServer {
        const self = try allocator.create(IpcServer);
        self.* = .{
            .allocator = allocator,
            .socket_path = try allocator.dupe(u8, socket_path),
        };
        return self;
    }

    pub fn deinit(self: *IpcServer) void {
        self.allocator.free(self.socket_path);
        self.allocator.destroy(self);
    }

    pub fn listen(_: *IpcServer) !void {
        // TODO: Implement Unix domain socket server
    }

    pub fn accept(_: *IpcServer) !?*IpcClient {
        return null;
    }
};

pub const IpcClient = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,

    pub fn connect(allocator: std.mem.Allocator, socket_path: []const u8) !*IpcClient {
        const self = try allocator.create(IpcClient);
        self.* = .{
            .allocator = allocator,
            .socket_path = try allocator.dupe(u8, socket_path),
        };
        return self;
    }

    pub fn deinit(self: *IpcClient) void {
        self.allocator.free(self.socket_path);
        self.allocator.destroy(self);
    }

    pub fn send(_: *IpcClient, _: Message) !void {
        // TODO: Implement send
    }

    pub fn receive(_: *IpcClient) !?Message {
        return null;
    }
};
