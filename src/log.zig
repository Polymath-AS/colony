const std = @import("std");

pub const Level = enum(u3) {
    err = 0,
    warn = 1,
    info = 2,
    debug = 3,

    pub fn asText(self: Level) []const u8 {
        return switch (self) {
            .err => "ERROR",
            .warn => "WARN",
            .info => "INFO",
            .debug => "DEBUG",
        };
    }
};

pub const Scope = enum {
    session,
    workspace,
    registry,
    pty,
    c_api,

    pub fn asText(self: Scope) []const u8 {
        return switch (self) {
            .session => "session",
            .workspace => "workspace",
            .registry => "registry",
            .pty => "pty",
            .c_api => "c_api",
        };
    }
};

var log_level: Level = .info;
var enabled: bool = true;

pub fn setLevel(level: Level) void {
    log_level = level;
}

pub fn setEnabled(e: bool) void {
    enabled = e;
}

pub fn scoped(comptime scope: Scope) type {
    return struct {
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            log(.err, scope, fmt, args);
        }

        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            log(.warn, scope, fmt, args);
        }

        pub fn info(comptime fmt: []const u8, args: anytype) void {
            log(.info, scope, fmt, args);
        }

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            log(.debug, scope, fmt, args);
        }
    };
}

fn log(comptime level: Level, comptime scope: Scope, comptime fmt: []const u8, args: anytype) void {
    if (!enabled) return;
    if (@intFromEnum(level) > @intFromEnum(log_level)) return;

    const file = std.posix.STDERR_FILENO;
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[{s}] [{s}] " ++ fmt ++ "\n", .{ level.asText(), scope.asText() } ++ args) catch return;
    _ = std.posix.write(file, msg) catch {};
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    log(.err, .c_api, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log(.warn, .c_api, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(.info, .c_api, fmt, args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(.debug, .c_api, fmt, args);
}
