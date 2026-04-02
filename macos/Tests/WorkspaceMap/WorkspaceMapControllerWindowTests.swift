import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapControllerWindowTests: XCTestCase {
    func testProgrammaticWindowAttachesHostingViewBeforeDisplay() {
        let controller = WorkspaceMapController(Ghostty.App())

        let contentView = try? XCTUnwrap(controller.window?.contentView)
        XCTAssertNotNil(contentView)
        XCTAssertEqual(controller.window?.delegate as? WorkspaceMapController, controller)
        XCTAssertTrue(
            String(describing: type(of: contentView!)).contains("NSHostingView"),
            "Expected Workspace Map window content to be backed by NSHostingView before showWindow."
        )
    }
}
