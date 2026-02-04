import SwiftUI
import ColonyCore

struct ContentView: View {
    @State private var store = WorkspaceStore()
    @State private var selectedWorkspace: WorkspaceInfo?

    var body: some View {
        NavigationSplitView {
            List(store.workspaces, selection: $selectedWorkspace) { ws in
                Text(ws.name)
                    .tag(ws)
            }
            .navigationTitle("Workspaces")
            .toolbar {
                Button(action: createDefaultWorkspace) {
                    Image(systemName: "plus")
                }
            }
        } detail: {
            if let ws = selectedWorkspace {
                VStack {
                    Text(ws.name)
                        .font(.title)
                    Text(ws.path)
                        .foregroundStyle(.secondary)
                    TerminalHostView(sessionId: ColonySessionId())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Select a workspace")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            initializeApp()
        }
    }

    private func initializeApp() {
        store.loadWorkspaces()
        if store.workspaces.isEmpty {
            createDefaultWorkspace()
        }
        selectedWorkspace = store.workspaces.first
    }

    private func createDefaultWorkspace() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let wsId = store.createWorkspace(name: "Home", path: home) {
            store.loadWorkspaces()
            store.openWorkspace(wsId)
        }
    }
}

#Preview {
    ContentView()
}
