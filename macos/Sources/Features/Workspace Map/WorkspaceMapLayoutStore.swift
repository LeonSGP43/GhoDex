import Foundation

final class WorkspaceMapLayoutStore {
    static let shared = WorkspaceMapLayoutStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "workspace-map.layout.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> WorkspaceMapLayoutSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard let snapshot = try? decoder.decode(WorkspaceMapLayoutSnapshot.self, from: data) else {
            return nil
        }
        guard snapshot.schemaVersion == .v1 else { return nil }
        return snapshot
    }

    func save(_ snapshot: WorkspaceMapLayoutSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
