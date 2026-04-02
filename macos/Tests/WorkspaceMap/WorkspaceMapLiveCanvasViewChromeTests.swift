import XCTest
import AppKit
@testable import GhoDex

@MainActor
final class WorkspaceMapLiveCanvasViewChromeTests: XCTestCase {
    func testLiveNodeHeaderDoesNotRenderKindBadgeText() {
        let suiteName = "WorkspaceMapLiveCanvasViewChromeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let groupID = WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111")
        let layoutStore = WorkspaceMapLayoutStore(defaults: defaults, storageKey: "layout")
        let model = WorkspaceMapViewModel(
            projectionSource: {
                WorkspaceMapSnapshot(groups: [])
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: layoutStore
        )

        let host = WorkspaceMapCanvasHostView(model: model, contentProvider: nil)
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)

        let snapshot = WorkspaceMapSnapshot(groups: [
            WorkspaceMapGroupSnapshot(
                id: groupID,
                kind: .terminal,
                title: "Terminal Alpha",
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
                    centerX: 320,
                    centerY: 280,
                    isCollapsed: false
                ),
            ]
        )

        host.update(snapshot: snapshot, layout: layout, isPresentationActive: false)
        host.layoutSubtreeIfNeeded()

        let labelTexts = textLabels(in: host).map { $0.uppercased() }
        XCTAssertFalse(labelTexts.contains("TERMINAL"))
        XCTAssertFalse(labelTexts.contains("BROWSER"))
    }

    private func textLabels(in root: NSView) -> [String] {
        var values: [String] = []

        if let label = root as? NSTextField, !label.stringValue.isEmpty {
            values.append(label.stringValue)
        }

        for subview in root.subviews {
            values.append(contentsOf: textLabels(in: subview))
        }

        return values
    }
}
