import XCTest
import AppKit
@testable import GhoDex

final class WorkspaceMapCanvasInputPolicyTests: XCTestCase {
    func testModifierKeysForceZoom() {
        let mode = WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: true,
            deltaX: 0,
            deltaY: 8,
            modifierFlags: [.command]
        )

        XCTAssertEqual(mode, .zoom)
    }

    func testShiftForcesPan() {
        let mode = WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: false,
            deltaX: 0,
            deltaY: 6,
            modifierFlags: [.shift]
        )

        XCTAssertEqual(mode, .pan)
    }

    func testPreciseScrollingDefaultsToZoom() {
        let mode = WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: true,
            deltaX: 0,
            deltaY: 10,
            modifierFlags: []
        )

        XCTAssertEqual(mode, .zoom)
    }

    func testNonPreciseVerticalWheelDefaultsToZoom() {
        let mode = WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: false,
            deltaX: 0,
            deltaY: 4,
            modifierFlags: []
        )

        XCTAssertEqual(mode, .zoom)
    }

    func testNonPreciseHorizontalDominantWheelPans() {
        let mode = WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: false,
            deltaX: 12,
            deltaY: 6,
            modifierFlags: []
        )

        XCTAssertEqual(mode, .pan)
    }

    func testFocusShortcutDirectionUsesCommandControlJKLI() {
        XCTAssertEqual(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "i",
                modifierFlags: [.command, .control]
            ),
            .up
        )
        XCTAssertEqual(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "k",
                modifierFlags: [.command, .control]
            ),
            .down
        )
        XCTAssertEqual(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "j",
                modifierFlags: [.command, .control]
            ),
            .left
        )
        XCTAssertEqual(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "l",
                modifierFlags: [.command, .control]
            ),
            .right
        )

        XCTAssertNil(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "m",
                modifierFlags: [.command, .control]
            )
        )
        XCTAssertNil(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "i",
                modifierFlags: [.option]
            )
        )
        XCTAssertNil(
            WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
                charactersIgnoringModifiers: "i",
                modifierFlags: [.command]
            )
        )
    }

    func testTopLevelNewTabShortcutMatchesCommandTOnly() {
        XCTAssertTrue(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command],
                keyCode: 17
            )
        )

        XCTAssertFalse(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command, .shift],
                keyCode: 17
            )
        )

        XCTAssertFalse(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.option],
                keyCode: 17
            )
        )
    }

    func testTopLevelNewTabShortcutFallsBackToKeyCode() {
        XCTAssertTrue(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command],
                keyCode: 17
            )
        )

        XCTAssertFalse(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command],
                keyCode: 4
            )
        )
    }

    func testTopLevelNewTabShortcutAllowsCommandWithUnrelatedFlags() {
        XCTAssertTrue(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command, .numericPad],
                keyCode: 17
            )
        )

        XCTAssertFalse(
            WorkspaceMapCanvasInputPolicy.isTopLevelNewTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command, .option, .numericPad],
                keyCode: 17
            )
        )
    }
}
