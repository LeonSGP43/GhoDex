import Testing
@testable import GhoDex

private struct LegacyTerminalRestorablePayload: Codable {
    let focusedSurface: String?
    let surfaceTree: SplitTree<TerminalPane>
    let effectiveFullscreenMode: FullscreenMode?
    let tabColor: TerminalTabColor
    let titleOverride: String?
}

@MainActor
struct TerminalWorkspaceSnapshotTests {
    @Test func terminalRestorableStateRoundTripsWorkspaceSnapshot() throws {
        let focusedSurfaceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let workspace = TerminalWorkspaceSnapshot(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Build Workspace",
            surfaceTree: .init(),
            focusedSurfaceID: focusedSurfaceID,
            effectiveFullscreenMode: .nonNative,
            tabColor: .orange,
            switcherMode: .sidebar)

        let data = try JSONEncoder().encode(TerminalRestorableState(workspace: workspace))
        let decoded = try JSONDecoder().decode(TerminalRestorableState.self, from: data)

        #expect(decoded.workspace.id == workspace.id)
        #expect(decoded.workspace.title == workspace.title)
        #expect(decoded.workspace.focusedSurfaceID == focusedSurfaceID)
        #expect(decoded.workspace.effectiveFullscreenMode == .nonNative)
        #expect(decoded.workspace.tabColor == .orange)
        #expect(decoded.workspace.switcherMode == .sidebar)
        #expect(decoded.surfaceTree.isEmpty)
    }

    @Test func terminalRestorableStateDecodesLegacyWindowStateIntoWorkspaceSnapshot() throws {
        let focusedSurfaceID = UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!
        let legacy = LegacyTerminalRestorablePayload(
            focusedSurface: focusedSurfaceID.uuidString,
            surfaceTree: .init(),
            effectiveFullscreenMode: .native,
            tabColor: .purple,
            titleOverride: "Legacy Workspace")

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(TerminalRestorableState.self, from: data)

        #expect(decoded.workspace.title == "Legacy Workspace")
        #expect(decoded.workspace.focusedSurfaceID == focusedSurfaceID)
        #expect(decoded.workspace.effectiveFullscreenMode == .native)
        #expect(decoded.workspace.tabColor == .purple)
        #expect(decoded.workspace.switcherMode == .top)
        #expect(decoded.surfaceTree.isEmpty)
    }
}
