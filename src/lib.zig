pub const workspace = @import("workspace.zig");
pub const session = @import("session.zig");
pub const persistence = @import("persistence.zig");
pub const registry = @import("registry.zig");
pub const apprt = @import("apprt/apprt.zig");

pub const c_api = @import("c_api.zig");

comptime {
    _ = c_api;
}

pub const Workspace = workspace.Workspace;
pub const WorkspaceId = workspace.WorkspaceId;
pub const Session = session.Session;
pub const SessionId = session.SessionId;
pub const SessionState = session.SessionState;
pub const Registry = registry.Registry;

test {
    @import("std").testing.refAllDecls(@This());
}
