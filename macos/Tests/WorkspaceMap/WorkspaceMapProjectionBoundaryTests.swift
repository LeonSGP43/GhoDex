import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapProjectionBoundaryTests: XCTestCase {
    func testNilRootTerminalGroupHasZeroCountsAndNilRootNode() throws {
        let runtime = WorkspaceMapRuntimeState(
            terminalGroups: [
                WorkspaceMapRuntimeTerminalGroup(
                    workspaceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    title: "Terminal",
                    isFocused: false,
                    root: nil
                ),
            ],
            browserGroups: []
        )

        let snapshot = WorkspaceMapProjectionService.makeSnapshot(from: runtime)
        let terminalGroup = try XCTUnwrap(snapshot.groups.first)
        let terminal = try XCTUnwrap(terminalGroup.terminal)

        XCTAssertEqual(terminal.splitCount, 0)
        XCTAssertEqual(terminal.paneCount, 0)
        XCTAssertEqual(terminal.tabCount, 0)
        XCTAssertNil(terminal.rootNodeID)
    }

    func testSnapshotPayloadContainsNoRuntimeTypeNames() throws {
        let runtime = WorkspaceMapRuntimeState(
            terminalGroups: [
                WorkspaceMapRuntimeTerminalGroup(
                    workspaceID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                    title: "Terminal",
                    isFocused: true,
                    root: .pane(
                        WorkspaceMapRuntimePane(
                            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                            isFocused: true,
                            tabs: [
                                WorkspaceMapRuntimePaneTab(
                                    id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
                                    title: "tab",
                                    isActive: true
                                ),
                            ]
                        )
                    )
                ),
            ],
            browserGroups: []
        )

        let snapshot = WorkspaceMapProjectionService.makeSnapshot(
            from: runtime,
            now: Date(timeIntervalSince1970: 2)
        )

        let data = try JSONEncoder().encode(snapshot)
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(payload.contains("Ghostty"))
        XCTAssertFalse(payload.contains("SurfaceView"))
        XCTAssertFalse(payload.contains("NSView"))
        XCTAssertFalse(payload.contains("TerminalController"))
    }
}
