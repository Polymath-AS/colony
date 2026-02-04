import SwiftUI
import AppKit
import ColonyCore

struct TerminalHostView: NSViewRepresentable {
    let sessionId: ColonySessionId

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Will be replaced with Ghostty surface
    }
}
