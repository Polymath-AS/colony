const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const workspace = @import("workspace.zig");
const session = @import("session.zig");

pub const DbError = error{
    OpenFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    MigrationFailed,
    OutOfMemory,
};

pub const WorkspaceDb = struct {
    db: *c.sqlite3,
    allocator: std.mem.Allocator,

    const SCHEMA_VERSION: i32 = 1;

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !*WorkspaceDb {
        const self = try allocator.create(WorkspaceDb);
        errdefer allocator.destroy(self);

        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path_z.ptr, &db);
        if (rc != c.SQLITE_OK or db == null) {
            if (db) |d| _ = c.sqlite3_close(d);
            return DbError.OpenFailed;
        }

        self.* = .{
            .db = db.?,
            .allocator = allocator,
        };

        return self;
    }

    pub fn close(self: *WorkspaceDb) void {
        _ = c.sqlite3_close(self.db);
        self.allocator.destroy(self);
    }

    pub fn migrate(self: *WorkspaceDb) !void {
        const version = try self.getSchemaVersion();

        if (version < 1) {
            try self.exec(
                \\CREATE TABLE IF NOT EXISTS workspace_meta (
                \\  key TEXT PRIMARY KEY,
                \\  value TEXT NOT NULL
                \\);
                \\
                \\CREATE TABLE IF NOT EXISTS sessions (
                \\  id BLOB PRIMARY KEY,
                \\  state INTEGER NOT NULL,
                \\  cwd TEXT,
                \\  shell TEXT,
                \\  title TEXT,
                \\  cols INTEGER NOT NULL,
                \\  rows INTEGER NOT NULL,
                \\  exit_code INTEGER,
                \\  created_at INTEGER NOT NULL,
                \\  updated_at INTEGER NOT NULL
                \\);
                \\
                \\CREATE TABLE IF NOT EXISTS session_env (
                \\  session_id BLOB NOT NULL,
                \\  key TEXT NOT NULL,
                \\  value TEXT NOT NULL,
                \\  PRIMARY KEY (session_id, key),
                \\  FOREIGN KEY (session_id) REFERENCES sessions(id)
                \\);
                \\
                \\CREATE TABLE IF NOT EXISTS command_history (
                \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
                \\  session_id BLOB NOT NULL,
                \\  command TEXT NOT NULL,
                \\  exit_code INTEGER,
                \\  started_at INTEGER NOT NULL,
                \\  ended_at INTEGER,
                \\  FOREIGN KEY (session_id) REFERENCES sessions(id)
                \\);
                \\
                \\CREATE INDEX IF NOT EXISTS idx_command_history_session
                \\  ON command_history(session_id);
                \\CREATE INDEX IF NOT EXISTS idx_command_history_started
                \\  ON command_history(started_at DESC);
            );
            try self.setSchemaVersion(1);
        }
    }

    fn getSchemaVersion(self: *WorkspaceDb) !i32 {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "PRAGMA user_version;",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            return c.sqlite3_column_int(stmt, 0);
        }
        return 0;
    }

    fn setSchemaVersion(self: *WorkspaceDb, version: i32) !void {
        var buf: [64]u8 = undefined;
        const sql = std.fmt.bufPrint(&buf, "PRAGMA user_version = {d};", .{version}) catch
            return DbError.MigrationFailed;

        const sql_z = self.allocator.dupeZ(u8, sql) catch return DbError.OutOfMemory;
        defer self.allocator.free(sql_z);

        const rc = c.sqlite3_exec(self.db, sql_z.ptr, null, null, null);
        if (rc != c.SQLITE_OK) return DbError.MigrationFailed;
    }

    fn exec(self: *WorkspaceDb, sql: [:0]const u8) !void {
        const rc = c.sqlite3_exec(self.db, sql.ptr, null, null, null);
        if (rc != c.SQLITE_OK) return DbError.MigrationFailed;
    }

    pub fn saveWorkspaceMeta(self: *WorkspaceDb, ws: *workspace.Workspace) !void {
        try self.setMeta("name", ws.name);

        var buf1: [24]u8 = undefined;
        const created = std.fmt.bufPrint(&buf1, "{d}", .{ws.created_at}) catch return DbError.OutOfMemory;
        try self.setMeta("created_at", created);

        var buf2: [24]u8 = undefined;
        const updated = std.fmt.bufPrint(&buf2, "{d}", .{ws.updated_at}) catch return DbError.OutOfMemory;
        try self.setMeta("updated_at", updated);
    }

    pub fn loadWorkspaceMeta(self: *WorkspaceDb, ws: *workspace.Workspace) !void {
        if (try self.getMeta("name")) |name| {
            self.allocator.free(ws.name);
            ws.name = name;
        }
    }

    fn setMeta(self: *WorkspaceDb, key: []const u8, value: []const u8) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "INSERT OR REPLACE INTO workspace_meta (key, value) VALUES (?, ?);",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), null);
        _ = c.sqlite3_bind_text(stmt, 2, value.ptr, @intCast(value.len), null);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn getMeta(self: *WorkspaceDb, key: []const u8) !?[]const u8 {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "SELECT value FROM workspace_meta WHERE key = ?;",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), null);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const text = c.sqlite3_column_text(stmt, 0);
            const len: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));
            if (text != null and len > 0) {
                return try self.allocator.dupe(u8, text[0..len]);
            }
        }
        return null;
    }

    pub fn saveSession(self: *WorkspaceDb, sess: *session.Session) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            \\INSERT OR REPLACE INTO sessions
            \\  (id, state, cwd, shell, title, cols, rows, exit_code, created_at, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        ,
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_blob(stmt, 1, &sess.id.bytes, 16, null);
        _ = c.sqlite3_bind_int(stmt, 2, @intFromEnum(sess.state));

        if (sess.cwd) |cwd| {
            _ = c.sqlite3_bind_text(stmt, 3, cwd.ptr, @intCast(cwd.len), null);
        } else {
            _ = c.sqlite3_bind_null(stmt, 3);
        }

        if (sess.shell) |shell| {
            _ = c.sqlite3_bind_text(stmt, 4, shell.ptr, @intCast(shell.len), null);
        } else {
            _ = c.sqlite3_bind_null(stmt, 4);
        }

        if (sess.title) |title| {
            _ = c.sqlite3_bind_text(stmt, 5, title.ptr, @intCast(title.len), null);
        } else {
            _ = c.sqlite3_bind_null(stmt, 5);
        }

        _ = c.sqlite3_bind_int(stmt, 6, sess.size.cols);
        _ = c.sqlite3_bind_int(stmt, 7, sess.size.rows);

        if (sess.exit_code) |code| {
            _ = c.sqlite3_bind_int(stmt, 8, code);
        } else {
            _ = c.sqlite3_bind_null(stmt, 8);
        }

        _ = c.sqlite3_bind_int64(stmt, 9, sess.created_at);
        _ = c.sqlite3_bind_int64(stmt, 10, sess.updated_at);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;

        try self.saveSessionEnv(sess);
    }

    fn saveSessionEnv(self: *WorkspaceDb, sess: *session.Session) !void {
        var del_stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(
            self.db,
            "DELETE FROM session_env WHERE session_id = ?;",
            -1,
            &del_stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(del_stmt);

        _ = c.sqlite3_bind_blob(del_stmt, 1, &sess.id.bytes, 16, null);
        if (c.sqlite3_step(del_stmt) != c.SQLITE_DONE) return DbError.StepFailed;

        var it = sess.env.iterator();
        while (it.next()) |entry| {
            var ins_stmt: ?*c.sqlite3_stmt = null;
            rc = c.sqlite3_prepare_v2(
                self.db,
                "INSERT INTO session_env (session_id, key, value) VALUES (?, ?, ?);",
                -1,
                &ins_stmt,
                null,
            );
            if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(ins_stmt);

            _ = c.sqlite3_bind_blob(ins_stmt, 1, &sess.id.bytes, 16, null);
            _ = c.sqlite3_bind_text(ins_stmt, 2, entry.key_ptr.*.ptr, @intCast(entry.key_ptr.*.len), null);
            _ = c.sqlite3_bind_text(ins_stmt, 3, entry.value_ptr.*.ptr, @intCast(entry.value_ptr.*.len), null);

            if (c.sqlite3_step(ins_stmt) != c.SQLITE_DONE) return DbError.StepFailed;
        }
    }

    fn loadSessionEnv(self: *WorkspaceDb, sess: *session.Session) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "SELECT key, value FROM session_env WHERE session_id = ?;",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_blob(stmt, 1, &sess.id.bytes, 16, null);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const key_ptr = c.sqlite3_column_text(stmt, 0);
            const key_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));
            const val_ptr = c.sqlite3_column_text(stmt, 1);
            const val_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 1));

            if (key_ptr != null and val_ptr != null) {
                const key = try sess.allocator.dupe(u8, key_ptr[0..key_len]);
                errdefer sess.allocator.free(key);
                const val = try sess.allocator.dupe(u8, val_ptr[0..val_len]);
                try sess.env.put(key, val);
            }
        }
    }

    pub fn loadSessions(self: *WorkspaceDb, allocator: std.mem.Allocator, ws_id: workspace.WorkspaceId) !std.ArrayListUnmanaged(*session.Session) {
        var sessions = std.ArrayListUnmanaged(*session.Session){};
        errdefer {
            for (sessions.items) |s| s.deinit();
            sessions.deinit(allocator);
        }

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "SELECT id, state, cwd, shell, title, cols, rows, exit_code, created_at, updated_at FROM sessions;",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const sess = try allocator.create(session.Session);
            errdefer allocator.destroy(sess);

            const id_blob = c.sqlite3_column_blob(stmt, 0);
            var id_bytes: [16]u8 = undefined;
            if (id_blob != null) {
                @memcpy(&id_bytes, @as([*]const u8, @ptrCast(id_blob))[0..16]);
            }

            sess.* = .{
                .id = .{ .bytes = id_bytes },
                .workspace_id = ws_id,
                .state = @enumFromInt(@as(u8, @intCast(c.sqlite3_column_int(stmt, 1)))),
                .cwd = null,
                .shell = null,
                .title = null,
                .size = .{
                    .cols = @intCast(c.sqlite3_column_int(stmt, 5)),
                    .rows = @intCast(c.sqlite3_column_int(stmt, 6)),
                },
                .ghostty_handle = .{},
                .exit_code = null,
                .created_at = c.sqlite3_column_int64(stmt, 8),
                .updated_at = c.sqlite3_column_int64(stmt, 9),
                .allocator = allocator,
                .env = std.StringHashMap([]const u8).init(allocator),
            };

            if (c.sqlite3_column_type(stmt, 7) != c.SQLITE_NULL) {
                sess.exit_code = c.sqlite3_column_int(stmt, 7);
            }

            try self.loadSessionEnv(sess);
            try sessions.append(allocator, sess);
        }

        return sessions;
    }

    pub fn deleteSession(self: *WorkspaceDb, sess_id: session.SessionId) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(
            self.db,
            "DELETE FROM session_env WHERE session_id = ?;",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_blob(stmt, 1, &sess_id.bytes, 16, null);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;

        var del_stmt: ?*c.sqlite3_stmt = null;
        rc = c.sqlite3_prepare_v2(
            self.db,
            "DELETE FROM sessions WHERE id = ?;",
            -1,
            &del_stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(del_stmt);

        _ = c.sqlite3_bind_blob(del_stmt, 1, &sess_id.bytes, 16, null);
        if (c.sqlite3_step(del_stmt) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn addCommandHistory(
        self: *WorkspaceDb,
        sess_id: session.SessionId,
        command: []const u8,
        started_at: i64,
    ) !i64 {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.db,
            "INSERT INTO command_history (session_id, command, started_at) VALUES (?, ?, ?);",
            -1,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_blob(stmt, 1, &sess_id.bytes, 16, null);
        _ = c.sqlite3_bind_text(stmt, 2, command.ptr, @intCast(command.len), null);
        _ = c.sqlite3_bind_int64(stmt, 3, started_at);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;

        return c.sqlite3_last_insert_rowid(self.db);
    }
};
