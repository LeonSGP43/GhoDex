import XCTest
@testable import GhoDex

final class WorkspaceMapLayoutStoreTests: XCTestCase {
    func testLoadClampsViewportAndGroupCoordinates() {
        let suiteName = "WorkspaceMapLayoutStoreTests.clamp.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = WorkspaceMapLayoutStore(defaults: defaults, storageKey: "layout")
        let snapshot = WorkspaceMapLayoutSnapshot(
            viewport: WorkspaceMapViewportSnapshot(offsetX: 500_000, offsetY: -500_000, zoom: 9.9),
            groups: [
                WorkspaceMapGroupLayoutSnapshot(
                    id: WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111"),
                    centerX: 2_000_000,
                    centerY: -2_000_000,
                    isCollapsed: false
                ),
            ]
        )

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded?.viewport.offsetX, 200_000)
        XCTAssertEqual(loaded?.viewport.offsetY, -200_000)
        XCTAssertEqual(loaded?.viewport.zoom, 2.2)
        XCTAssertEqual(loaded?.groups.first?.centerX, 1_000_000)
        XCTAssertEqual(loaded?.groups.first?.centerY, -1_000_000)
    }

    func testLoadClampsLowZoomBound() {
        let suiteName = "WorkspaceMapLayoutStoreTests.low-zoom.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = WorkspaceMapLayoutStore(defaults: defaults, storageKey: "layout")
        let snapshot = WorkspaceMapLayoutSnapshot(
            viewport: WorkspaceMapViewportSnapshot(offsetX: 0, offsetY: 0, zoom: 0.1),
            groups: []
        )

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded?.viewport.zoom, 0.45)
    }
}
