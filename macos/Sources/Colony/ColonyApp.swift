import SwiftUI
import ColonyCore

@main
struct ColonyApp: App {
    init() {
        log.info("Colony starting up")

        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Colony")
            .path

        log.debug("Config directory: \(configDir)")
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let result = colony_init(configDir)
        if result != COLONY_OK {
            log.error("Failed to initialize Colony core: \(result.rawValue)")
        } else {
            log.info("Colony core initialized")
        }

        Task { @MainActor in
            GhosttyBridge.shared.setup()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
