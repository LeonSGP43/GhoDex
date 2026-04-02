import Foundation

final class WorkspaceMapLayoutStore {
    static let shared = WorkspaceMapLayoutStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum LayoutSanitizer {
        static let minZoom: Double = 0.45
        static let maxZoom: Double = 2.2
        static let maxViewportMagnitude: Double = 200_000
        static let maxLogicalCoordinateMagnitude: Double = 1_000_000
        static let fallbackCenterX: Double = 160
        static let fallbackCenterY: Double = 120
    }

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
        return sanitize(snapshot)
    }

    func save(_ snapshot: WorkspaceMapLayoutSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func sanitize(_ snapshot: WorkspaceMapLayoutSnapshot) -> WorkspaceMapLayoutSnapshot {
        var sanitized = snapshot
        sanitized.viewport.offsetX = sanitizeViewportValue(sanitized.viewport.offsetX)
        sanitized.viewport.offsetY = sanitizeViewportValue(sanitized.viewport.offsetY)
        sanitized.viewport.zoom = sanitizeZoom(sanitized.viewport.zoom)
        sanitized.groups = sanitized.groups.map { group in
            WorkspaceMapGroupLayoutSnapshot(
                id: group.id,
                centerX: sanitizeGroupCoordinate(group.centerX, fallback: LayoutSanitizer.fallbackCenterX),
                centerY: sanitizeGroupCoordinate(group.centerY, fallback: LayoutSanitizer.fallbackCenterY),
                isCollapsed: group.isCollapsed
            )
        }
        return sanitized
    }

    private func sanitizeZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, LayoutSanitizer.minZoom), LayoutSanitizer.maxZoom)
    }

    private func sanitizeViewportValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -LayoutSanitizer.maxViewportMagnitude), LayoutSanitizer.maxViewportMagnitude)
    }

    private func sanitizeGroupCoordinate(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, -LayoutSanitizer.maxLogicalCoordinateMagnitude), LayoutSanitizer.maxLogicalCoordinateMagnitude)
    }
}
