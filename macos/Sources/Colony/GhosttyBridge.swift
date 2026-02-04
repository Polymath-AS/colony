import Foundation
import ColonyCore

@MainActor
class GhosttyBridge {
    static let shared = GhosttyBridge()

    private var callbacks: ColonyGhosttyCallbacks?

    private init() {}

    func setup() {
        log.info("Setting up Ghostty bridge")

        var callbacks = ColonyGhosttyCallbacks()
        callbacks.on_output = { sessId, data, len in
            guard let data = data else { return }
            let bytes = Array(UnsafeBufferPointer(start: data, count: len))
            Task { @MainActor in
                GhosttyBridge.shared.handleOutput(sessionId: sessId, data: bytes)
            }
        }
        callbacks.on_title_change = { sessId, title in
            guard let title = title else { return }
            let str = String(cString: title)
            Task { @MainActor in
                GhosttyBridge.shared.handleTitleChange(sessionId: sessId, title: str)
            }
        }
        callbacks.on_cwd_change = { sessId, cwd in
            guard let cwd = cwd else { return }
            let str = String(cString: cwd)
            Task { @MainActor in
                GhosttyBridge.shared.handleCwdChange(sessionId: sessId, cwd: str)
            }
        }
        callbacks.on_exit = { sessId, exitCode in
            Task { @MainActor in
                GhosttyBridge.shared.handleExit(sessionId: sessId, exitCode: exitCode)
            }
        }
        callbacks.on_bell = { sessId in
            Task { @MainActor in
                GhosttyBridge.shared.handleBell(sessionId: sessId)
            }
        }

        self.callbacks = callbacks
        withUnsafePointer(to: &self.callbacks!) { ptr in
            _ = colony_ghostty_set_callbacks(ptr)
        }

        log.debug("Ghostty callbacks registered")
    }

    private func handleOutput(sessionId: ColonySessionId, data: [UInt8]) {
        log.debug("Ghostty output: \(data.count) bytes for session")
        // TODO: Route to terminal view
    }

    private func handleTitleChange(sessionId: ColonySessionId, title: String) {
        log.debug("Ghostty title change: \(title)")
        // TODO: Update window/tab title
    }

    private func handleCwdChange(sessionId: ColonySessionId, cwd: String) {
        log.debug("Ghostty cwd change: \(cwd)")
        // TODO: Update session cwd
    }

    private func handleExit(sessionId: ColonySessionId, exitCode: Int32) {
        log.info("Ghostty session exited with code: \(exitCode)")
        // TODO: Handle session cleanup
    }

    private func handleBell(sessionId: ColonySessionId) {
        log.debug("Ghostty bell")
        // TODO: Play bell sound or flash
    }

    func write(workspaceId: ColonyWorkspaceId, sessionId: ColonySessionId, data: [UInt8]) {
        data.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = colony_ghostty_write(workspaceId, sessionId, baseAddress, ptr.count)
        }
    }
}
