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
}
