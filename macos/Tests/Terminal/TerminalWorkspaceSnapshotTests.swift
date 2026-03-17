import AppKit
import Testing
@testable import GhoDex

private struct LegacyTerminalRestorablePayload: Codable {
    let focusedSurface: String?
    let surfaceTree: SplitTree<TerminalPane>
    let effectiveFullscreenMode: FullscreenMode?
    let tabColor: TerminalTabColor
    let titleOverride: String?
}

private struct PersistedSurface: Codable, Identifiable, Equatable {
    let id: UUID
    let pwd: String?
    let title: String
    let isUserSetTitle: Bool

    private enum CodingKeys: String, CodingKey {
        case pwd
        case uuid
        case title
        case isUserSetTitle
    }

    init(id: UUID, pwd: String?, title: String, isUserSetTitle: Bool) {
        self.id = id
        self.pwd = pwd
        self.title = title
        self.isUserSetTitle = isUserSetTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try #require(
            UUID(uuidString: container.decode(String.self, forKey: .uuid)),
            "Persisted surface UUID should be valid")
        self.pwd = try container.decodeIfPresent(String.self, forKey: .pwd)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.isUserSetTitle = try container.decodeIfPresent(Bool.self, forKey: .isUserSetTitle) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pwd, forKey: .pwd)
        try container.encode(id.uuidString, forKey: .uuid)
        try container.encode(title, forKey: .title)
        try container.encode(isUserSetTitle, forKey: .isUserSetTitle)
    }
}

private final class PersistedPane: NSView, Codable, Identifiable {
    let id: UUID
    let surfaces: [PersistedSurface]
    let activeSurfaceID: UUID

    var activeSurface: PersistedSurface {
        surfaces.first(where: { $0.id == activeSurfaceID }) ?? surfaces[0]
    }

    init(id: UUID, surfaces: [PersistedSurface], activeSurfaceID: UUID) {
        precondition(!surfaces.isEmpty, "PersistedPane requires at least one surface")
        self.id = id
        self.surfaces = surfaces
        self.activeSurfaceID = surfaces.contains(where: { $0.id == activeSurfaceID })
            ? activeSurfaceID
            : surfaces[0].id
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for PersistedPane")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case surfaces
        case activeSurfaceID
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSurfaces = try container.decode([PersistedSurface].self, forKey: .surfaces)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.surfaces = decodedSurfaces
        let decodedActiveID = try container.decode(UUID.self, forKey: .activeSurfaceID)
        self.activeSurfaceID = decodedSurfaces.contains(where: { $0.id == decodedActiveID })
            ? decodedActiveID
            : try #require(decodedSurfaces.first?.id, "PersistedPane requires at least one surface")
        super.init(frame: .zero)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surfaces, forKey: .surfaces)
        try container.encode(activeSurfaceID, forKey: .activeSurfaceID)
    }
}

private struct PersistedWorkspaceSnapshot: Codable {
    let id: UUID
    let title: String?
    let surfaceTree: SplitTree<PersistedPane>
    let focusedSurfaceID: UUID?
    let effectiveFullscreenMode: FullscreenMode?
    let tabColor: TerminalTabColor
    let switcherMode: TerminalWorkspaceSwitcherMode
}

private struct PersistedRestorableState: Codable {
    let workspace: PersistedWorkspaceSnapshot
}

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
        #expect(decoded.workspace.switcherMode == TerminalWorkspaceSwitcherMode.sidebar)
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

    @Test @MainActor func terminalRestorableStateRoundTripsWorkspacePaneHierarchy() throws {
        let leftPaneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let rightPaneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

        let leftSurface1 = PersistedSurface(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            pwd: "/tmp/workspace/left/1",
            title: "left-1",
            isUserSetTitle: false)
        let leftSurface2 = PersistedSurface(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            pwd: "/tmp/workspace/left/2",
            title: "left-2",
            isUserSetTitle: true)
        let rightSurface1 = PersistedSurface(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            pwd: "/tmp/workspace/right/1",
            title: "right-1",
            isUserSetTitle: false)
        let rightSurface2 = PersistedSurface(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            pwd: "/tmp/workspace/right/2",
            title: "right-2",
            isUserSetTitle: true)

        let leftPane = PersistedPane(
            id: leftPaneID,
            surfaces: [leftSurface1, leftSurface2],
            activeSurfaceID: leftSurface2.id)
        let rightPane = PersistedPane(
            id: rightPaneID,
            surfaces: [rightSurface1, rightSurface2],
            activeSurfaceID: rightSurface1.id)

        var surfaceTree = SplitTree<PersistedPane>(view: leftPane)
        surfaceTree = try surfaceTree.inserting(view: rightPane, at: leftPane, direction: SplitTree<PersistedPane>.NewDirection.right)

        let workspace = PersistedWorkspaceSnapshot(
            id: UUID(uuidString: "33333333-2222-1111-4444-555555555555")!,
            title: "Pane Workspace",
            surfaceTree: surfaceTree,
            focusedSurfaceID: leftSurface2.id,
            effectiveFullscreenMode: .nonNative,
            tabColor: .blue,
            switcherMode: .sidebar)

        let data = try JSONEncoder().encode(PersistedRestorableState(workspace: workspace))
        let decoded = try JSONDecoder().decode(PersistedRestorableState.self, from: data)

        #expect(decoded.workspace.id == workspace.id)
        #expect(decoded.workspace.focusedSurfaceID == leftSurface2.id)
        #expect(decoded.workspace.switcherMode == TerminalWorkspaceSwitcherMode.sidebar)

        guard case .split(let rootSplit) = decoded.workspace.surfaceTree.root,
              case .leaf(let decodedLeftPane) = rootSplit.left,
              case .leaf(let decodedRightPane) = rootSplit.right else {
            Issue.record("Expected a split tree with left and right pane leaves after round-trip")
            return
        }

        #expect(rootSplit.direction == .horizontal)
        #expect(decodedLeftPane.id == leftPaneID)
        #expect(decodedRightPane.id == rightPaneID)

        #expect(decodedLeftPane.surfaces.map { $0.id } == [leftSurface1.id, leftSurface2.id])
        #expect(decodedRightPane.surfaces.map { $0.id } == [rightSurface1.id, rightSurface2.id])
        #expect(decodedLeftPane.surfaces.map(\.pwd) == [leftSurface1.pwd, leftSurface2.pwd])
        #expect(decodedRightPane.surfaces.map(\.pwd) == [rightSurface1.pwd, rightSurface2.pwd])
        #expect(decodedLeftPane.surfaces.map(\.title) == [leftSurface1.title, leftSurface2.title])
        #expect(decodedRightPane.surfaces.map(\.title) == [rightSurface1.title, rightSurface2.title])
        #expect(decodedLeftPane.surfaces.map(\.isUserSetTitle) == [leftSurface1.isUserSetTitle, leftSurface2.isUserSetTitle])
        #expect(decodedRightPane.surfaces.map(\.isUserSetTitle) == [rightSurface1.isUserSetTitle, rightSurface2.isUserSetTitle])

        #expect(decodedLeftPane.activeSurfaceID == leftSurface2.id)
        #expect(decodedRightPane.activeSurfaceID == rightSurface1.id)
        #expect(decodedLeftPane.activeSurface.id == leftSurface2.id)
        #expect(decodedRightPane.activeSurface.id == rightSurface1.id)
    }
}
