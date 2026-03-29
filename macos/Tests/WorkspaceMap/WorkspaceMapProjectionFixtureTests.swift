import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapProjectionFixtureTests: XCTestCase {
    func testEmptyFixtureProjectsEmptySnapshot() {
        let snapshot = WorkspaceMapProjectionService.makeSnapshot(
            from: .empty,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.groups, [])
        XCTAssertEqual(snapshot.schemaVersion, .v1)
    }

    func testSplitHierarchyProjectsStableIDsAndParentChildLinks() throws {
        let runtime = makeDeterministicRuntimeState()
        let snapshot = WorkspaceMapProjectionService.makeSnapshot(
            from: runtime,
            now: Date(timeIntervalSince1970: 100)
        )

        let terminalGroup = try XCTUnwrap(snapshot.groups.first(where: { $0.kind == .terminal }))
        let terminal = try XCTUnwrap(terminalGroup.terminal)
        XCTAssertEqual(terminal.splitCount, 1)
        XCTAssertEqual(terminal.paneCount, 2)
        XCTAssertEqual(terminal.tabCount, 3)
        XCTAssertEqual(
            terminal.rootNodeID?.rawValue,
            "split:terminal-group:11111111-1111-1111-1111-111111111111:root"
        )

        let root = try XCTUnwrap(terminal.nodes.first(where: { $0.id == terminal.rootNodeID }))
        XCTAssertEqual(root.kind, .split)
        XCTAssertEqual(root.splitDirection, .horizontal)
        XCTAssertEqual(try XCTUnwrap(root.splitRatio), 0.6, accuracy: 0.0001)
        XCTAssertEqual(root.childIDs.count, 2)

        let leftPane = try XCTUnwrap(terminal.nodes.first(where: { $0.id == root.childIDs[0] }))
        let rightPane = try XCTUnwrap(terminal.nodes.first(where: { $0.id == root.childIDs[1] }))
        XCTAssertEqual(leftPane.kind, .pane)
        XCTAssertEqual(rightPane.kind, .pane)
        XCTAssertEqual(leftPane.parentID, root.id)
        XCTAssertEqual(rightPane.parentID, root.id)

        let activeTab = terminal.nodes.first(where: { $0.kind == .paneTab && $0.isActive })
        XCTAssertEqual(activeTab?.id.rawValue, "pane-tab:33333333-3333-3333-3333-333333333333")
    }

    func testMultiGroupSortsByKindThenID() {
        let runtime = makeDeterministicRuntimeState()
        let snapshot = WorkspaceMapProjectionService.makeSnapshot(
            from: runtime,
            now: Date(timeIntervalSince1970: 100)
        )
        let groupIDs = snapshot.groups.map(\.id.rawValue)

        XCTAssertEqual(groupIDs, [
            "browser-group:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "browser-group:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "terminal-group:11111111-1111-1111-1111-111111111111",
            "terminal-group:22222222-2222-2222-2222-222222222222",
        ])
    }

    func testSameInputAndClockProducesByteIdenticalJSON() throws {
        let runtime = makeDeterministicRuntimeState()
        let now = Date(timeIntervalSince1970: 333)

        let lhs = WorkspaceMapProjectionService.makeSnapshot(from: runtime, now: now)
        let rhs = WorkspaceMapProjectionService.makeSnapshot(from: runtime, now: now)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let lhsJSON = try XCTUnwrap(String(data: encoder.encode(lhs), encoding: .utf8))
        let rhsJSON = try XCTUnwrap(String(data: encoder.encode(rhs), encoding: .utf8))
        XCTAssertEqual(lhsJSON, rhsJSON)
    }

    private func makeDeterministicRuntimeState() -> WorkspaceMapRuntimeState {
        let terminalWorkspace1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let terminalWorkspace2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let browserWorkspaceA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let browserWorkspaceB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let paneLeft = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000001")!
        let paneRight = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000002")!

        return WorkspaceMapRuntimeState(
            terminalGroups: [
                WorkspaceMapRuntimeTerminalGroup(
                    workspaceID: terminalWorkspace2,
                    title: "Terminal B",
                    isFocused: false,
                    root: .pane(
                        WorkspaceMapRuntimePane(
                            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000010")!,
                            isFocused: false,
                            tabs: [
                                WorkspaceMapRuntimePaneTab(
                                    id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000020")!,
                                    title: "B-Tab-1",
                                    isActive: true
                                ),
                            ]
                        )
                    )
                ),
                WorkspaceMapRuntimeTerminalGroup(
                    workspaceID: terminalWorkspace1,
                    title: "Terminal A",
                    isFocused: true,
                    root: .split(
                        direction: .horizontal,
                        ratio: 0.6,
                        left: .pane(
                            WorkspaceMapRuntimePane(
                                id: paneLeft,
                                isFocused: true,
                                tabs: [
                                    WorkspaceMapRuntimePaneTab(
                                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                                        title: "A-Tab-1",
                                        isActive: true
                                    ),
                                    WorkspaceMapRuntimePaneTab(
                                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333334")!,
                                        title: "A-Tab-2",
                                        isActive: false
                                    ),
                                ]
                            )
                        ),
                        right: .pane(
                            WorkspaceMapRuntimePane(
                                id: paneRight,
                                isFocused: false,
                                tabs: [
                                    WorkspaceMapRuntimePaneTab(
                                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333335")!,
                                        title: "A-Right-1",
                                        isActive: true
                                    ),
                                ]
                            )
                        )
                    )
                ),
            ],
            browserGroups: [
                WorkspaceMapRuntimeBrowserGroup(
                    workspaceID: browserWorkspaceB,
                    title: "Browser B",
                    isFocused: false,
                    selectedPageID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                    displayedURL: "https://b.example"
                ),
                WorkspaceMapRuntimeBrowserGroup(
                    workspaceID: browserWorkspaceA,
                    title: "Browser A",
                    isFocused: false,
                    selectedPageID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                    displayedURL: "https://a.example"
                ),
            ]
        )
    }
}
