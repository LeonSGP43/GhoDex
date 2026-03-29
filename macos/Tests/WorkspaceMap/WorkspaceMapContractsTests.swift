import XCTest
@testable import GhoDex

final class WorkspaceMapContractsTests: XCTestCase {
    func testWorkspaceMapEntityIDFactoriesAndParsers() {
        let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let browserWorkspaceID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let paneID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let paneTabID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let browserExternalID = "browser-tab-abc"

        let terminalGroupID = WorkspaceMapEntityID.terminalGroup(workspaceID)
        let browserWorkspaceGroupID = WorkspaceMapEntityID.browserGroup(browserWorkspaceID)
        let browserGroupID = WorkspaceMapEntityID.browserGroup(browserExternalID)
        let paneEntityID = WorkspaceMapEntityID.pane(paneID)
        let paneTabEntityID = WorkspaceMapEntityID.paneTab(paneTabID)
        let splitEntityID = WorkspaceMapEntityID.split(groupID: terminalGroupID, path: [.left, .right])

        XCTAssertEqual(terminalGroupID.terminalGroupUUID, workspaceID)
        XCTAssertEqual(browserWorkspaceGroupID.browserGroupUUID, browserWorkspaceID)
        XCTAssertEqual(browserGroupID.browserGroupExternalID, browserExternalID)
        XCTAssertEqual(paneEntityID.paneUUID, paneID)
        XCTAssertEqual(paneTabEntityID.paneTabUUID, paneTabID)
        XCTAssertEqual(
            splitEntityID.rawValue,
            "split:terminal-group:11111111-1111-1111-1111-111111111111:l.r"
        )
    }

    func testWorkspaceMapCommandPolicyAllowsOnlyV1Commands() {
        XCTAssertTrue(WorkspaceMapCommandPolicy.isAllowedInV1(.focusTopLevelGroup))
        XCTAssertTrue(WorkspaceMapCommandPolicy.isAllowedInV1(.renameTopLevelGroup))
        XCTAssertTrue(WorkspaceMapCommandPolicy.isAllowedInV1(.closeTopLevelGroup))
        XCTAssertTrue(WorkspaceMapCommandPolicy.isAllowedInV1(.jumpToTerminalPaneTab))
        XCTAssertFalse(WorkspaceMapCommandPolicy.isAllowedInV1(.editSplitTree))
    }

    func testWorkspaceMapSnapshotDefaultsToV1Schema() {
        let snapshot = WorkspaceMapSnapshot(groups: [])
        XCTAssertEqual(snapshot.schemaVersion, .v1)
    }

    func testWorkspaceMapSnapshotSemanticEqualityIgnoresTimestamp() {
        let group = WorkspaceMapGroupSnapshot(
            id: WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111"),
            kind: .terminal,
            title: "Terminal",
            isFocused: false,
            terminal: WorkspaceMapTerminalGroupSnapshot(
                rootNodeID: nil,
                splitCount: 0,
                paneCount: 0,
                tabCount: 0,
                nodes: []
            ),
            browser: nil
        )

        let lhs = WorkspaceMapSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1),
            groups: [group]
        )
        let rhs = WorkspaceMapSnapshot(
            generatedAt: Date(timeIntervalSince1970: 2),
            groups: [group]
        )

        XCTAssertTrue(lhs.semanticallyEquals(rhs))
    }

    func testPerformanceThresholdsMatchPlanContract() {
        let largeA = WorkspaceMapPerformanceBudget.threshold(for: .largeA)
        XCTAssertEqual(largeA.snapshotBuildP95MS, 25)
        XCTAssertEqual(largeA.snapshotBuildP99MS, 40)
        XCTAssertEqual(largeA.publishCadenceMaxPerSecond, 12)
        XCTAssertEqual(largeA.mainThreadSpikeMaxCount, 2)
        XCTAssertEqual(largeA.commandLatencyP95MS, 50)
        XCTAssertEqual(largeA.commandFailureRateMax, 0)

        let largeB = WorkspaceMapPerformanceBudget.threshold(for: .largeB)
        XCTAssertEqual(largeB.snapshotBuildP95MS, 20)
        XCTAssertEqual(largeB.snapshotBuildP99MS, 35)
        XCTAssertEqual(largeB.publishCadenceMaxPerSecond, 20)
        XCTAssertEqual(largeB.mainThreadSpikeMaxCount, 5)
        XCTAssertEqual(largeB.commandLatencyP95MS, 55)
        XCTAssertEqual(largeB.commandFailureRateMax, 0)

        let largeC = WorkspaceMapPerformanceBudget.threshold(for: .largeC)
        XCTAssertEqual(largeC.snapshotBuildP95MS, 20)
        XCTAssertEqual(largeC.snapshotBuildP99MS, 35)
        XCTAssertEqual(largeC.publishCadenceMaxPerSecond, 15)
        XCTAssertEqual(largeC.mainThreadSpikeMaxCount, 3)
        XCTAssertEqual(largeC.commandLatencyP95MS, 45)
        XCTAssertEqual(largeC.commandFailureRateMax, 0)
    }

    @MainActor
    func testCommandHandlerBlocksSplitTreeEditByPolicy() {
        let request = WorkspaceMapCommandRequest(
            command: .editSplitTree,
            targetID: WorkspaceMapEntityID("split:any")
        )

        let result = WorkspaceMapCommandHandler.execute(request)
        XCTAssertEqual(result.status, .blockedByPolicy)
    }

    @MainActor
    func testCommandHandlerRejectsInvalidJumpTarget() {
        let request = WorkspaceMapCommandRequest(
            command: .jumpToTerminalPaneTab,
            targetID: WorkspaceMapEntityID("pane:22222222-2222-2222-2222-222222222222")
        )

        let result = WorkspaceMapCommandHandler.execute(request)
        XCTAssertEqual(result.status, .invalidRequest)
    }
}
