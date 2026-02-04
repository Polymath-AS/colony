import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Colony")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Terminal-first workspace manager")
                .foregroundStyle(.secondary)
            
            Text("Swift runtime stub - Ghostty integration pending")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}

#Preview {
    ContentView()
}
