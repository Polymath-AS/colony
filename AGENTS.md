# Colony

Terminal-first multi-workspace application with Zig core and SwiftUI/GTK clients.

## Build Commands

```bash
zig build          # Build library
zig build test     # Run tests
```

## Architecture

- **src/**: Zig core library with C ABI
  - `workspace.zig`: Workspace model with strict isolation
  - `session.zig`: Terminal session lifecycle
  - `registry.zig`: Workspace registry (JSON persistence)
  - `persistence.zig`: SQLite per-workspace storage
  - `c_api.zig`: C ABI exports for Swift/GTK
  - `include/colony.h`: C header for FFI
  - **apprt/**: Application runtime abstraction (Ghostty-style)
    - `apprt.zig`: Runtime switching via build_config (none|gtk|swift)
    - `structs.zig`: Shared types (SurfaceId, SurfaceSize, TerminalSize, ContentScale)
    - `surface.zig`: Surface state machine and lifecycle
    - `ipc.zig`: IPC message types and client/server interfaces
    - `none.zig`: No-op runtime for testing/headless
    - `swift.zig`: Swift runtime stub (macOS, Swift owns main loop)
    - `gtk/gtk.zig`: GTK runtime stub (Linux, not yet implemented)
- **macos/**: Swift package with SwiftUI app
  - `Sources/Colony/ColonyApp.swift`: App entry point
  - `Sources/ColonyCore/`: C bridge modulemap

## Key Concepts

- **Window-scoped workspaces**: Each window pins to one workspace
- **Strict isolation**: No shared sessions/env/state across workspaces
- **SQLite per workspace**: `{workspace_path}/.colony/workspace.db`
- **Registry**: `{config_dir}/workspaces.json` for workspace list

## C ABI Usage

```c
#include "colony.h"

colony_init("/path/to/config");
ColonyWorkspaceId ws_id;
colony_workspace_create("my-project", "/path/to/project", &ws_id);
colony_workspace_open(ws_id);

ColonySessionId sess_id;
colony_session_create(ws_id, &sess_id);
colony_session_start(ws_id, sess_id);

colony_shutdown();
```
