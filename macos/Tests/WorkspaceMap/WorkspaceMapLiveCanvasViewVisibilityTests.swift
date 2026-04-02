import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapLiveCanvasViewVisibilityTests: XCTestCase {
    func testDeferredAutoCenterRunsAfterBoundsBecomeAvailable() {
        let suiteName = "WorkspaceMapLiveCanvasViewVisibilityTests.deferred-center.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let groupID = WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111")
        let layoutStore = WorkspaceMapLayoutStore(defaults: defaults, storageKey: "layout")
        layoutStore.save(
            WorkspaceMapLayoutSnapshot(
                viewport: WorkspaceMapViewportSnapshot(offsetX: 0, offsetY: 0, zoom: 1),
                groups: [
                    WorkspaceMapGroupLayoutSnapshot(
                        id: groupID,
                        centerX: 5_000,
                        centerY: 4_000,
                        isCollapsed: false
                    ),
                ]
            )
        )

        let model = WorkspaceMapViewModel(
            projectionSource: {
                WorkspaceMapSnapshot(groups: [
                    WorkspaceMapGroupSnapshot(
                        id: groupID,
                        kind: .terminal,
                        title: "Terminal",
                        isFocused: true,
                        terminal: WorkspaceMapTerminalGroupSnapshot(
                            rootNodeID: nil,
                            splitCount: 0,
                            paneCount: 0,
                            tabCount: 0,
                            nodes: []
                        ),
                        browser: nil
                    ),
                ])
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: layoutStore
        )
        model.setViewportOffset(.zero)

        let host = WorkspaceMapCanvasHostView(model: model, contentProvider: nil)
        let snapshot = WorkspaceMapSnapshot(groups: [
            WorkspaceMapGroupSnapshot(
                id: groupID,
                kind: .terminal,
                title: "Terminal",
                isFocused: true,
                terminal: WorkspaceMapTerminalGroupSnapshot(
                    rootNodeID: nil,
                    splitCount: 0,
                    paneCount: 0,
                    tabCount: 0,
                    nodes: []
                ),
                browser: nil
            ),
        ])
        let layout = WorkspaceMapLayoutSnapshot(
            viewport: WorkspaceMapViewportSnapshot(offsetX: 0, offsetY: 0, zoom: 1),
            groups: [
                WorkspaceMapGroupLayoutSnapshot(
                    id: groupID,
                    centerX: 5_000,
                    centerY: 4_000,
                    isCollapsed: false
                ),
            ]
        )

        host.frame = .zero
        host.update(snapshot: snapshot, layout: layout, isPresentationActive: false)

        XCTAssertEqual(model.viewportOffset.width, 0, accuracy: 0.001)
        XCTAssertEqual(model.viewportOffset.height, 0, accuracy: 0.001)

        host.frame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        host.layout()

        XCTAssertEqual(model.viewportOffset.width, -4_500, accuracy: 0.1)
        XCTAssertEqual(model.viewportOffset.height, -3_650, accuracy: 0.1)
    }
}
