const std = @import("std");
const posix = std.posix;
const log = @import("log.zig").scoped(.pty);

fn allocPrintZ(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![:0]const u8 {
    const slice = try std.fmt.allocPrint(allocator, fmt, args);
    const new_len = slice.len + 1;
    const result: []u8 = if (allocator.resize(slice, new_len))
        slice.ptr[0..new_len]
    else blk: {
        const new_buf = try allocator.alloc(u8, new_len);
        @memcpy(new_buf[0..slice.len], slice);
        allocator.free(slice);
        break :blk new_buf;
    };
    result[slice.len] = 0;
    return result[0..slice.len :0];
}

pub const PtyError = error{
    OpenFailed,
    ForkFailed,
    ExecFailed,
    SetupFailed,
    AlreadySpawned,
    NotSpawned,
    WriteFailed,
    ReadFailed,
    OutOfMemory,
    InvalidPty,
};

pub const Pty = struct {
    master_fd: posix.fd_t,
    slave_fd: ?posix.fd_t,
    child_pid: ?posix.pid_t,
    allocator: std.mem.Allocator,

    pub fn open(allocator: std.mem.Allocator) !*Pty {
        const self = try allocator.create(Pty);
        errdefer allocator.destroy(self);

        const result = posix.openat(posix.AT.FDCWD, "/dev/ptmx", .{
            .ACCMODE = .RDWR,
            .NOCTTY = true,
            .CLOEXEC = true,
        }, 0) catch {
            log.err("failed to open /dev/ptmx", .{});
            return PtyError.OpenFailed;
        };

        self.* = .{
            .master_fd = result,
            .slave_fd = null,
            .child_pid = null,
            .allocator = allocator,
        };

        grantpt(self.master_fd) catch |e| {
            log.err("grantpt failed: {}", .{e});
            posix.close(self.master_fd);
            allocator.destroy(self);
            return PtyError.SetupFailed;
        };

        unlockpt(self.master_fd) catch |e| {
            log.err("unlockpt failed: {}", .{e});
            posix.close(self.master_fd);
            allocator.destroy(self);
            return PtyError.SetupFailed;
        };

        log.debug("pty opened, master_fd={d}", .{self.master_fd});
        return self;
    }

    pub fn spawn(
        self: *Pty,
        shell: []const u8,
        cwd: ?[]const u8,
        env_map: ?*const std.StringHashMap([]const u8),
        size: struct { cols: u16, rows: u16 },
    ) !void {
        if (self.child_pid != null) return PtyError.AlreadySpawned;

        const slave_path = ptsname(self.master_fd) orelse {
            log.err("ptsname failed", .{});
            return PtyError.SetupFailed;
        };

        log.debug("slave path: {s}", .{slave_path});

        setSize(self.master_fd, size.cols, size.rows);

        const slave_fd = posix.openatZ(posix.AT.FDCWD, slave_path, .{
            .ACCMODE = .RDWR,
            .NOCTTY = true,
        }, 0) catch {
            log.err("failed to open slave pty", .{});
            return PtyError.OpenFailed;
        };
        self.slave_fd = slave_fd;

        const pid = posix.fork() catch {
            log.err("fork failed", .{});
            return PtyError.ForkFailed;
        };

        if (pid == 0) {
            posix.close(self.master_fd);

            _ = posix.setsid() catch {};

            _ = std.c.ioctl(slave_fd, TIOCSCTTY, @as(?*anyopaque, null));

            posix.dup2(slave_fd, 0) catch posix.exit(126);
            posix.dup2(slave_fd, 1) catch posix.exit(126);
            posix.dup2(slave_fd, 2) catch posix.exit(126);

            if (slave_fd > 2) posix.close(slave_fd);

            if (cwd) |dir| {
                posix.chdir(dir) catch {};
            }

            var env_list = std.ArrayListUnmanaged(?[*:0]const u8){};
            defer env_list.deinit(self.allocator);

            if (env_map) |em| {
                var it = em.iterator();
                while (it.next()) |entry| {
                    const combined = allocPrintZ(self.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch continue;
                    env_list.append(self.allocator, combined) catch continue;
                }
            }

            const default_env = [_][*:0]const u8{
                "TERM=xterm-256color",
                "COLORTERM=truecolor",
                "LANG=en_US.UTF-8",
            };
            for (default_env) |e| {
                env_list.append(self.allocator, e) catch continue;
            }
            env_list.append(self.allocator, null) catch {};

            const shell_z = self.allocator.dupeZ(u8, shell) catch posix.exit(127);
            const argv = [_:null]?[*:0]const u8{ shell_z, null };

            const env_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(env_list.items.ptr);

            posix.execvpeZ(shell_z, &argv, env_ptr) catch posix.exit(127);
            posix.exit(127);
        }

        posix.close(slave_fd);
        self.slave_fd = null;
        self.child_pid = pid;

        log.info("spawned shell pid={d} shell={s}", .{ pid, shell });
    }

    pub fn write(self: *Pty, data: []const u8) !usize {
        if (self.child_pid == null) return PtyError.NotSpawned;
        return posix.write(self.master_fd, data) catch {
            log.err("write to pty failed", .{});
            return PtyError.WriteFailed;
        };
    }

    pub fn read(self: *Pty, buf: []u8) !usize {
        if (self.child_pid == null) return PtyError.NotSpawned;
        return posix.read(self.master_fd, buf) catch |e| {
            if (e == error.WouldBlock) return 0;
            log.err("read from pty failed: {}", .{e});
            return PtyError.ReadFailed;
        };
    }

    pub fn resize(self: *Pty, cols: u16, rows: u16) void {
        setSize(self.master_fd, cols, rows);
        log.debug("resized pty cols={d} rows={d}", .{ cols, rows });
    }

    pub fn kill(self: *Pty) void {
        if (self.child_pid) |pid| {
            _ = posix.kill(pid, posix.SIG.TERM) catch {};
            log.debug("sent SIGTERM to pid={d}", .{pid});
        }
    }

    pub fn waitExit(self: *Pty) ?i32 {
        if (self.child_pid) |pid| {
            const result = posix.waitpid(pid, posix.W.NOHANG);
            if (result.pid != 0) {
                self.child_pid = null;
                const status = result.status;
                if (posix.W.IFEXITED(status)) {
                    const code = posix.W.EXITSTATUS(status);
                    log.info("child exited with code={d}", .{code});
                    return @intCast(code);
                }
                if (posix.W.IFSIGNALED(status)) {
                    const sig = posix.W.TERMSIG(status);
                    log.info("child killed by signal={d}", .{sig});
                    return -@as(i32, @intCast(sig));
                }
            }
        }
        return null;
    }

    pub fn getMasterFd(self: *Pty) posix.fd_t {
        return self.master_fd;
    }

    pub fn close(self: *Pty) void {
        self.kill();

        if (self.child_pid) |pid| {
            _ = posix.waitpid(pid, 0);
            self.child_pid = null;
        }

        if (self.slave_fd) |fd| {
            posix.close(fd);
            self.slave_fd = null;
        }

        posix.close(self.master_fd);
        log.debug("pty closed", .{});
        self.allocator.destroy(self);
    }
};

const TIOCPTYGNAME: c_ulong = 0x40807453;
const TIOCSWINSZ: c_ulong = 0x80087467;
const TIOCSCTTY: c_ulong = 0x20007461;

fn grantpt(_: posix.fd_t) !void {
    // macOS doesn't require explicit grantpt/unlockpt for /dev/ptmx
}

fn unlockpt(_: posix.fd_t) !void {
    // macOS doesn't require explicit grantpt/unlockpt for /dev/ptmx
}

fn ptsname(fd: posix.fd_t) ?[:0]const u8 {
    var buf: [128:0]u8 = undefined;
    const rc = std.c.ioctl(fd, TIOCPTYGNAME, &buf);
    if (rc < 0) return null;
    const len = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
    return buf[0..len :0];
}

fn setSize(fd: posix.fd_t, cols: u16, rows: u16) void {
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16 = 0,
        ws_ypixel: u16 = 0,
    };
    var ws = winsize{ .ws_row = rows, .ws_col = cols };
    _ = std.c.ioctl(fd, @as(c_int, @bitCast(@as(u32, @truncate(TIOCSWINSZ)))), &ws);
}

test "pty open and close" {
    const allocator = std.testing.allocator;
    const pty = try Pty.open(allocator);
    pty.close();
}
