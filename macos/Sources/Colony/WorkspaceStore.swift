import Foundation
import ColonyCore

struct WorkspaceInfo: Identifiable, Hashable {
    let id: ColonyWorkspaceId
    let name: String
    let path: String
    let lastOpened: Int64
}

extension ColonyWorkspaceId: @retroactive Hashable {
    public static func == (lhs: ColonyWorkspaceId, rhs: ColonyWorkspaceId) -> Bool {
        withUnsafeBytes(of: lhs.bytes) { lhsBytes in
            withUnsafeBytes(of: rhs.bytes) { rhsBytes in
                lhsBytes.elementsEqual(rhsBytes)
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        withUnsafeBytes(of: bytes) { hasher.combine(bytes: $0) }
    }
}

@MainActor @Observable
class WorkspaceStore {
    private(set) var workspaces: [WorkspaceInfo] = []
    private(set) var currentWorkspaceId: ColonyWorkspaceId?

    func loadWorkspaces() {
        let count = colony_workspace_count()
        log.debug("Loading workspaces (count=\(count))")
        guard count > 0 else {
            workspaces = []
            return
        }

        var infos = [ColonyWorkspaceInfo](repeating: ColonyWorkspaceInfo(), count: count)
        var actualCount: Int = 0

        let result = colony_workspace_list(&infos, count, &actualCount)
        guard result == COLONY_OK else {
            log.error("Failed to list workspaces: \(result.rawValue)")
            workspaces = []
            return
        }

        workspaces = infos.prefix(actualCount).map { info in
            WorkspaceInfo(
                id: info.id,
                name: info.name.map { String(cString: $0) } ?? "Unnamed",
                path: info.path.map { String(cString: $0) } ?? "",
                lastOpened: info.last_opened
            )
        }
        log.info("Loaded \(workspaces.count) workspaces")
    }

    func createWorkspace(name: String, path: String) -> ColonyWorkspaceId? {
        log.info("Creating workspace '\(name)' at \(path)")
        var wsId = ColonyWorkspaceId()
        let result = colony_workspace_create(name, path, &wsId)
        guard result == COLONY_OK else {
            log.error("Failed to create workspace: \(result.rawValue)")
            return nil
        }
        log.debug("Created workspace")
        return wsId
    }

    func openWorkspace(_ id: ColonyWorkspaceId) {
        log.debug("Opening workspace")
        let result = colony_workspace_open(id)
        if result == COLONY_OK {
            currentWorkspaceId = id
            log.info("Workspace opened")
        } else {
            log.error("Failed to open workspace: \(result.rawValue)")
        }
    }

    func deleteWorkspace(_ id: ColonyWorkspaceId) {
        log.info("Deleting workspace")
        let result = colony_workspace_delete(id)
        if result != COLONY_OK {
            log.error("Failed to delete workspace: \(result.rawValue)")
        }
    }
}
