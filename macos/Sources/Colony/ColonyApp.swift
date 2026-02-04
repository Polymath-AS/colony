import SwiftUI
import ColonyCore

@main
struct ColonyApp: App {
    init() {
        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Colony")
            .path
        
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        
        let result = colony_init(configDir)
        if result != COLONY_OK {
            print("Failed to initialize Colony: \(result)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
