#ifndef COLONY_H
#define COLONY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t bytes[16];
} ColonyWorkspaceId;

typedef struct {
    uint8_t bytes[16];
} ColonySessionId;

typedef enum {
    COLONY_SESSION_CREATED = 0,
    COLONY_SESSION_RUNNING = 1,
    COLONY_SESSION_SUSPENDED = 2,
    COLONY_SESSION_TERMINATED = 3
} ColonySessionState;

typedef struct {
    uint16_t cols;
    uint16_t rows;
} ColonyTerminalSize;

typedef struct {
    ColonyWorkspaceId id;
    const char* name;
    const char* path;
    int64_t last_opened;
} ColonyWorkspaceInfo;

typedef struct {
    ColonySessionId id;
    ColonyWorkspaceId workspace_id;
    ColonySessionState state;
    ColonyTerminalSize size;
    void* ghostty_handle;
} ColonySessionInfo;

typedef enum {
    COLONY_OK = 0,
    COLONY_ERR_NOT_INITIALIZED = -1,
    COLONY_ERR_INVALID_ID = -2,
    COLONY_ERR_NOT_FOUND = -3,
    COLONY_ERR_ALREADY_EXISTS = -4,
    COLONY_ERR_IO = -5,
    COLONY_ERR_INVALID_STATE = -6,
    COLONY_ERR_OUT_OF_MEMORY = -7
} ColonyResult;

// Lifecycle
ColonyResult colony_init(const char* config_dir);
void colony_shutdown(void);

// Workspace management
ColonyResult colony_workspace_create(const char* name, const char* path, ColonyWorkspaceId* out_id);
ColonyResult colony_workspace_open(ColonyWorkspaceId id);
ColonyResult colony_workspace_close(ColonyWorkspaceId id);
ColonyResult colony_workspace_delete(ColonyWorkspaceId id);
ColonyResult colony_workspace_list(ColonyWorkspaceInfo* out_list, size_t max_count, size_t* out_count);
size_t colony_workspace_count(void);

// Session management
ColonyResult colony_session_create(ColonyWorkspaceId ws_id, ColonySessionId* out_id);
ColonyResult colony_session_start(ColonyWorkspaceId ws_id, ColonySessionId sess_id);
ColonyResult colony_session_terminate(ColonyWorkspaceId ws_id, ColonySessionId sess_id, int exit_code);
ColonyResult colony_session_resize(ColonyWorkspaceId ws_id, ColonySessionId sess_id, uint16_t cols, uint16_t rows);
ColonyResult colony_session_bind_ghostty(ColonyWorkspaceId ws_id, ColonySessionId sess_id, void* handle);
ColonyResult colony_session_set_cwd(ColonyWorkspaceId ws_id, ColonySessionId sess_id, const char* cwd);
ColonyResult colony_session_set_shell(ColonyWorkspaceId ws_id, ColonySessionId sess_id, const char* shell);
ColonyResult colony_session_set_title(ColonyWorkspaceId ws_id, ColonySessionId sess_id, const char* title);
ColonyResult colony_session_set_env(ColonyWorkspaceId ws_id, ColonySessionId sess_id, const char* key, const char* value);
ColonyResult colony_session_delete(ColonyWorkspaceId ws_id, ColonySessionId sess_id);

// Ghostty integration callbacks
typedef void (*ColonyOutputCallback)(ColonySessionId sess_id, const uint8_t* data, size_t len);
typedef void (*ColonyTitleChangeCallback)(ColonySessionId sess_id, const char* title);
typedef void (*ColonyCwdChangeCallback)(ColonySessionId sess_id, const char* cwd);
typedef void (*ColonyExitCallback)(ColonySessionId sess_id, int exit_code);
typedef void (*ColonyBellCallback)(ColonySessionId sess_id);

typedef struct {
    ColonyOutputCallback on_output;
    ColonyTitleChangeCallback on_title_change;
    ColonyCwdChangeCallback on_cwd_change;
    ColonyExitCallback on_exit;
    ColonyBellCallback on_bell;
} ColonyGhosttyCallbacks;

ColonyResult colony_ghostty_set_callbacks(const ColonyGhosttyCallbacks* callbacks);
ColonyResult colony_ghostty_write(ColonyWorkspaceId ws_id, ColonySessionId sess_id, const uint8_t* data, size_t len);

// Ghostty notification functions (call from terminal to notify clients)
void colony_ghostty_notify_title(ColonySessionId sess_id, const char* title);
void colony_ghostty_notify_cwd(ColonySessionId sess_id, const char* cwd);
void colony_ghostty_notify_exit(ColonySessionId sess_id, int exit_code);
void colony_ghostty_notify_bell(ColonySessionId sess_id);

#ifdef __cplusplus
}
#endif

#endif // COLONY_H
