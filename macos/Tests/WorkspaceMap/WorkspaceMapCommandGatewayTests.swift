import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapCommandGatewayTests: XCTestCase {
    func testBlockedPolicyCommandDoesNotInvokeGateway() {
        let gateway = MockGateway()
        let request = WorkspaceMapCommandRequest(
            command: .editSplitTree,
            targetID: WorkspaceMapEntityID("split:any")
        )

        let result = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(result.status, .blockedByPolicy)
        XCTAssertEqual(gateway.invocations, [])
    }

    func testFocusTopLevelGroupRoutesThroughGateway() {
        let gateway = MockGateway()
        let target = WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111")
        let request = WorkspaceMapCommandRequest(command: .focusTopLevelGroup, targetID: target)

        let result = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(result.status, .executed)
        XCTAssertEqual(gateway.invocations, ["focus:\(target.rawValue)"])
    }

    func testRenameTopLevelGroupRoutesThroughGatewayWithTitle() {
        let gateway = MockGateway()
        let target = WorkspaceMapEntityID("browser-group:22222222-2222-2222-2222-222222222222")
        let request = WorkspaceMapCommandRequest(
            command: .renameTopLevelGroup,
            targetID: target,
            title: " Renamed "
        )

        _ = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(gateway.invocations, ["rename:\(target.rawValue): Renamed "])
    }

    func testCloseTopLevelGroupRoutesThroughGateway() {
        let gateway = MockGateway()
        let target = WorkspaceMapEntityID("browser-group:33333333-3333-3333-3333-333333333333")
        let request = WorkspaceMapCommandRequest(command: .closeTopLevelGroup, targetID: target)

        _ = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(gateway.invocations, ["close:\(target.rawValue)"])
    }

    func testJumpToPaneTabInvalidTargetReturnsInvalidRequest() {
        let gateway = MockGateway()
        let request = WorkspaceMapCommandRequest(
            command: .jumpToTerminalPaneTab,
            targetID: WorkspaceMapEntityID("pane:bad")
        )

        let result = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(result.status, .invalidRequest)
        XCTAssertEqual(gateway.invocations, [])
    }

    func testJumpToPaneTabRoutesThroughGateway() {
        let gateway = MockGateway()
        let target = WorkspaceMapEntityID("pane-tab:44444444-4444-4444-4444-444444444444")
        let request = WorkspaceMapCommandRequest(
            command: .jumpToTerminalPaneTab,
            targetID: target
        )

        _ = WorkspaceMapCommandHandler.execute(request, gateway: gateway)
        XCTAssertEqual(gateway.invocations, ["jump:\(target.rawValue)"])
    }
}

@MainActor
private final class MockGateway: WorkspaceMapCommandGateway {
    var invocations: [String] = []

    func focusTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        invocations.append("focus:\(targetID.rawValue)")
        return WorkspaceMapCommandResult(status: .executed, message: "ok")
    }

    func renameTopLevelGroup(
        _ targetID: WorkspaceMapEntityID,
        title: String?
    ) -> WorkspaceMapCommandResult {
        invocations.append("rename:\(targetID.rawValue):\(title ?? "nil")")
        return WorkspaceMapCommandResult(status: .executed, message: "ok")
    }

    func closeTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        invocations.append("close:\(targetID.rawValue)")
        return WorkspaceMapCommandResult(status: .executed, message: "ok")
    }

    func jumpToTerminalPaneTab(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        invocations.append("jump:\(targetID.rawValue)")
        return WorkspaceMapCommandResult(status: .executed, message: "ok")
    }
}
