import Testing
@testable import GhoDex

struct AppDelegateWorkspaceMapModeTests {
    @Test func activeWorkspaceMapClosesCurrentModeTab() {
        #expect(
            AppDelegate.resolveWorkspaceMapModeToggleAction(
                isCurrentWorkspaceMapActive: true,
                hasExistingWorkspaceMap: true
            ) == .closeActive
        )
    }

    @Test func existingWorkspaceMapFocusesExistingModeWindow() {
        #expect(
            AppDelegate.resolveWorkspaceMapModeToggleAction(
                isCurrentWorkspaceMapActive: false,
                hasExistingWorkspaceMap: true
            ) == .focusExisting
        )
    }

    @Test func missingWorkspaceMapOpensANewModeWindow() {
        #expect(
            AppDelegate.resolveWorkspaceMapModeToggleAction(
                isCurrentWorkspaceMapActive: false,
                hasExistingWorkspaceMap: false
            ) == .openNew
        )
    }

    @Test func workspaceMapShortcutMatchesOnlyCommandOptionM() {
        #expect(
            AppDelegate.isWorkspaceMapModeShortcut(
                charactersIgnoringModifiers: "m",
                modifierFlags: [.command, .option]
            )
        )

        #expect(
            !AppDelegate.isWorkspaceMapModeShortcut(
                charactersIgnoringModifiers: "m",
                modifierFlags: [.command, .shift]
            )
        )

        #expect(
            !AppDelegate.isWorkspaceMapModeShortcut(
                charactersIgnoringModifiers: "h",
                modifierFlags: [.command, .option]
            )
        )
    }

    @Test func workspaceMapShortcutFallsBackToKeyCodeM() {
        #expect(
            AppDelegate.isWorkspaceMapModeShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command, .option],
                keyCode: 46
            )
        )

        #expect(
            !AppDelegate.isWorkspaceMapModeShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command, .option],
                keyCode: 4
            )
        )
    }

    @Test func minimizeShortcutMatchesOnlyCommandM() {
        #expect(
            AppDelegate.isMinimizeShortcut(
                charactersIgnoringModifiers: "m",
                modifierFlags: [.command]
            )
        )

        #expect(
            !AppDelegate.isMinimizeShortcut(
                charactersIgnoringModifiers: "m",
                modifierFlags: [.command, .option]
            )
        )

        #expect(
            !AppDelegate.isMinimizeShortcut(
                charactersIgnoringModifiers: "h",
                modifierFlags: [.command]
            )
        )
    }

    @Test func minimizeShortcutFallsBackToKeyCodeM() {
        #expect(
            AppDelegate.isMinimizeShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command],
                keyCode: 46
            )
        )

        #expect(
            !AppDelegate.isMinimizeShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command, .shift],
                keyCode: 46
            )
        )
    }
}
