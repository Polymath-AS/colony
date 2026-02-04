const std = @import("std");
const workspace = @import("workspace.zig");
const session = @import("session.zig");
const registry = @import("registry.zig");
const log = @import("log.zig");

var global_allocator: std.mem.Allocator = std.heap.page_allocator;
var global_registry: ?*registry.Registry = null;

pub const ColonyWorkspaceId = extern struct {
    bytes: [16]u8,
};

pub const ColonySessionId = extern struct {
    bytes: [16]u8,
};

pub const ColonySessionState = enum(c_int) {
    created = 0,
    running = 1,
    suspended = 2,
    terminated = 3,
};

pub const ColonyTerminalSize = extern struct {
    cols: u16,
    rows: u16,
};

pub const ColonyWorkspaceInfo = extern struct {
    id: ColonyWorkspaceId,
    name: [*:0]const u8,
    path: [*:0]const u8,
    last_opened: i64,
};

pub const ColonySessionInfo = extern struct {
    id: ColonySessionId,
    workspace_id: ColonyWorkspaceId,
    state: ColonySessionState,
    size: ColonyTerminalSize,
    ghostty_handle: ?*anyopaque,
};

pub const ColonyResult = enum(c_int) {
    ok = 0,
    err_not_initialized = -1,
    err_invalid_id = -2,
    err_not_found = -3,
    err_already_exists = -4,
    err_io = -5,
    err_invalid_state = -6,
    err_out_of_memory = -7,
};

export fn colony_init(config_dir: [*:0]const u8) ColonyResult {
    if (global_registry != null) return .ok;

    const dir = std.mem.span(config_dir);
    global_registry = registry.Registry.init(global_allocator, dir) catch {
        return .err_out_of_memory;
    };

    global_registry.?.load() catch {
        return .err_io;
    };

    log.info("colony initialized config_dir={s}", .{dir});
    return .ok;
}

export fn colony_set_log_level(level: c_int) void {
    const lvl: log.Level = switch (level) {
        0 => .err,
        1 => .warn,
        2 => .info,
        else => .debug,
    };
    log.setLevel(lvl);
}

export fn colony_shutdown() void {
    if (global_registry) |reg| {
        reg.deinit();
        global_registry = null;
    }
}

export fn colony_workspace_create(
    name: [*:0]const u8,
    path: [*:0]const u8,
    out_id: *ColonyWorkspaceId,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const ws = reg.createWorkspace(
        std.mem.span(name),
        std.mem.span(path),
    ) catch {
        return .err_io;
    };

    out_id.* = .{ .bytes = ws.id.bytes };
    return .ok;
}

export fn colony_workspace_open(id: ColonyWorkspaceId) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const ws_id = workspace.WorkspaceId{ .bytes = id.bytes };
    _ = reg.openWorkspace(ws_id) catch {
        return .err_not_found;
    };

    return .ok;
}

export fn colony_workspace_close(id: ColonyWorkspaceId) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const ws_id = workspace.WorkspaceId{ .bytes = id.bytes };
    reg.closeWorkspace(ws_id);
    return .ok;
}

export fn colony_workspace_delete(id: ColonyWorkspaceId) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const ws_id = workspace.WorkspaceId{ .bytes = id.bytes };
    reg.deleteWorkspace(ws_id) catch {
        return .err_io;
    };

    return .ok;
}

export fn colony_workspace_list(
    out_list: [*]ColonyWorkspaceInfo,
    max_count: usize,
    out_count: *usize,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const entries = reg.listWorkspaces();
    const count = @min(entries.len, max_count);

    for (entries[0..count], 0..) |entry, i| {
        out_list[i] = .{
            .id = .{ .bytes = entry.id.bytes },
            .name = @ptrCast(entry.name.ptr),
            .path = @ptrCast(entry.path.ptr),
            .last_opened = entry.last_opened,
        };
    }

    out_count.* = count;
    return .ok;
}

export fn colony_workspace_count() usize {
    const reg = global_registry orelse return 0;
    return reg.listWorkspaces().len;
}

export fn colony_session_create(
    ws_id: ColonyWorkspaceId,
    out_id: *ColonySessionId,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sess = ws.createSession() catch {
        return .err_out_of_memory;
    };

    out_id.* = .{ .bytes = sess.id.bytes };
    return .ok;
}

export fn colony_session_start(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.start() catch return .err_invalid_state;
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_spawn(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.spawnShell() catch |e| {
        log.scoped(.c_api).err("session spawn failed: {}", .{e});
        return .err_invalid_state;
    };
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_get_pty_fd(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
) c_int {
    const reg = global_registry orelse return -1;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return -1;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return -1;

    return sess.getPtyFd() orelse -1;
}

export fn colony_session_poll_output(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    out_buf: [*]u8,
    buf_len: usize,
    out_len: *usize,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    const pty = sess.pty orelse {
        out_len.* = 0;
        return .ok;
    };

    if (pty.waitExit()) |code| {
        sess.terminate(code);
        ws.persistSession(sess) catch {};
        out_len.* = 0;
        return .ok;
    }

    const n = pty.read(out_buf[0..buf_len]) catch {
        out_len.* = 0;
        return .err_io;
    };

    out_len.* = n;
    return .ok;
}

export fn colony_session_terminate(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    exit_code: c_int,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.terminate(exit_code);
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_resize(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    cols: u16,
    rows: u16,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.resize(cols, rows);
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_bind_ghostty(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    handle: ?*anyopaque,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.bindGhostty(.{ .ptr = handle });

    return .ok;
}

export fn colony_session_set_cwd(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    cwd: [*:0]const u8,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.setCwd(std.mem.span(cwd)) catch return .err_out_of_memory;
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_set_shell(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    shell: [*:0]const u8,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.setShell(std.mem.span(shell)) catch return .err_out_of_memory;
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_set_title(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    title: [*:0]const u8,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.setTitle(std.mem.span(title)) catch return .err_out_of_memory;
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_set_env(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    key: [*:0]const u8,
    value: [*:0]const u8,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.setEnv(std.mem.span(key), std.mem.span(value)) catch return .err_out_of_memory;
    ws.persistSession(sess) catch return .err_io;

    return .ok;
}

export fn colony_session_delete(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    ws.deleteSession(sid) catch return .err_io;

    return .ok;
}

pub const GhosttyCallbacks = extern struct {
    on_output: ?*const fn (sess_id: ColonySessionId, data: [*]const u8, len: usize) callconv(.c) void,
    on_title_change: ?*const fn (sess_id: ColonySessionId, title: [*:0]const u8) callconv(.c) void,
    on_cwd_change: ?*const fn (sess_id: ColonySessionId, cwd: [*:0]const u8) callconv(.c) void,
    on_exit: ?*const fn (sess_id: ColonySessionId, exit_code: c_int) callconv(.c) void,
    on_bell: ?*const fn (sess_id: ColonySessionId) callconv(.c) void,
};

var ghostty_callbacks: ?GhosttyCallbacks = null;

export fn colony_ghostty_set_callbacks(callbacks: *const GhosttyCallbacks) ColonyResult {
    ghostty_callbacks = callbacks.*;
    return .ok;
}

export fn colony_ghostty_write(
    ws_id: ColonyWorkspaceId,
    sess_id: ColonySessionId,
    data: [*]const u8,
    len: usize,
) ColonyResult {
    const reg = global_registry orelse return .err_not_initialized;

    const wid = workspace.WorkspaceId{ .bytes = ws_id.bytes };
    const ws = reg.getWorkspace(wid) orelse return .err_not_found;

    const sid = session.SessionId{ .bytes = sess_id.bytes };
    const sess = ws.getSession(sid) orelse return .err_not_found;

    sess.writeInput(data[0..len]);
    return .ok;
}

export fn colony_ghostty_notify_title(sess_id: ColonySessionId, title: [*:0]const u8) void {
    if (ghostty_callbacks) |cb| {
        if (cb.on_title_change) |on_title| {
            on_title(sess_id, title);
        }
    }
}

export fn colony_ghostty_notify_cwd(sess_id: ColonySessionId, cwd: [*:0]const u8) void {
    if (ghostty_callbacks) |cb| {
        if (cb.on_cwd_change) |on_cwd| {
            on_cwd(sess_id, cwd);
        }
    }
}

export fn colony_ghostty_notify_exit(sess_id: ColonySessionId, exit_code: c_int) void {
    if (ghostty_callbacks) |cb| {
        if (cb.on_exit) |on_exit| {
            on_exit(sess_id, exit_code);
        }
    }
}

export fn colony_ghostty_notify_bell(sess_id: ColonySessionId) void {
    if (ghostty_callbacks) |cb| {
        if (cb.on_bell) |on_bell| {
            on_bell(sess_id);
        }
    }
}
