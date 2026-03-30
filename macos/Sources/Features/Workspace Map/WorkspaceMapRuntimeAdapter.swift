import Foundation

struct WorkspaceMapProjectionLabels: Hashable, Sendable {
    let paneTitle: String
    let splitTitle: String

    static let fallback = WorkspaceMapProjectionLabels(
        paneTitle: "Pane",
        splitTitle: "Split"
    )

    @MainActor
    static func capture(
        preferredLanguages: [String] = AppLanguageSetting.preferredLanguages()
    ) -> Self {
        Self(
            paneTitle: AppLocalization.localizedText(
                "Pane",
                preferredLanguages: preferredLanguages
            ),
            splitTitle: AppLocalization.localizedText(
                "Split",
                preferredLanguages: preferredLanguages
            )
        )
    }
}

/// Runtime-backed input model that can be projected into immutable Workspace Map snapshots.
struct WorkspaceMapRuntimeState: Hashable, Sendable {
    let captureSequence: UInt64
    let projectionLabels: WorkspaceMapProjectionLabels
    var terminalGroups: [WorkspaceMapRuntimeTerminalGroup]
    var browserGroups: [WorkspaceMapRuntimeBrowserGroup]

    init(
        captureSequence: UInt64 = 0,
        projectionLabels: WorkspaceMapProjectionLabels = .fallback,
        terminalGroups: [WorkspaceMapRuntimeTerminalGroup],
        browserGroups: [WorkspaceMapRuntimeBrowserGroup]
    ) {
        self.captureSequence = captureSequence
        self.projectionLabels = projectionLabels
        self.terminalGroups = terminalGroups
        self.browserGroups = browserGroups
    }

    static let empty = WorkspaceMapRuntimeState(terminalGroups: [], browserGroups: [])
}

struct WorkspaceMapRuntimeTerminalGroup: Hashable, Sendable {
    let workspaceID: UUID
    let title: String
    let isFocused: Bool
    let root: WorkspaceMapRuntimeTerminalNode?
}

struct WorkspaceMapRuntimeBrowserGroup: Hashable, Sendable {
    let workspaceID: UUID
    let title: String
    let isFocused: Bool
    let selectedPageID: String
    let displayedURL: String
}

struct WorkspaceMapRuntimePane: Hashable, Sendable {
    let id: UUID
    let isFocused: Bool
    let tabs: [WorkspaceMapRuntimePaneTab]
}

struct WorkspaceMapRuntimePaneTab: Hashable, Sendable {
    let id: UUID
    let title: String
    let isActive: Bool
}

indirect enum WorkspaceMapRuntimeTerminalNode: Hashable, Sendable {
    case pane(WorkspaceMapRuntimePane)
    case split(
        direction: WorkspaceMapSplitDirection,
        ratio: Double,
        left: WorkspaceMapRuntimeTerminalNode,
        right: WorkspaceMapRuntimeTerminalNode
    )
}

@MainActor
enum WorkspaceMapRuntimeAdapter {
    private static var lastCaptureSequence: UInt64 = 0

    static func capture() -> WorkspaceMapRuntimeState {
        let preferredLanguages = AppLanguageSetting.preferredLanguages()
        return WorkspaceMapRuntimeState(
            captureSequence: nextCaptureSequence(),
            projectionLabels: WorkspaceMapProjectionLabels.capture(
                preferredLanguages: preferredLanguages
            ),
            terminalGroups: TerminalController.all.map(makeTerminalGroup),
            browserGroups: BrowserTabController.all.map {
                makeBrowserGroup($0, preferredLanguages: preferredLanguages)
            }
        )
    }

    private static func nextCaptureSequence() -> UInt64 {
        lastCaptureSequence &+= 1
        return lastCaptureSequence
    }

    private static func makeTerminalGroup(_ controller: TerminalController) -> WorkspaceMapRuntimeTerminalGroup {
        let focusedSurfaceID = controller.effectiveFocusedSurface()?.id
        return WorkspaceMapRuntimeTerminalGroup(
            workspaceID: controller.workspaceID,
            title: controller.titleOverride ?? controller.window?.title ?? "Terminal",
            isFocused: controller.window?.isKeyWindow ?? false,
            root: controller.surfaceTree.root.map { makeTerminalNode($0, focusedSurfaceID: focusedSurfaceID) }
        )
    }

    private static func makeBrowserGroup(
        _ controller: BrowserTabController,
        preferredLanguages: [String]
    ) -> WorkspaceMapRuntimeBrowserGroup {
        WorkspaceMapRuntimeBrowserGroup(
            workspaceID: controller.workspaceID,
            title: controller.titleOverride ?? controller.window?.title ?? AppLocalization.localizedText(
                "Browser",
                preferredLanguages: preferredLanguages
            ),
            isFocused: controller.window?.isKeyWindow ?? false,
            selectedPageID: controller.model.selectedPageID.uuidString.lowercased(),
            displayedURL: controller.model.displayedURL
        )
    }

    private static func makeTerminalNode(
        _ node: SplitTree<TerminalPane>.Node,
        focusedSurfaceID: UUID?
    ) -> WorkspaceMapRuntimeTerminalNode {
        switch node {
        case .leaf(let pane):
            let tabs = pane.surfaces.map {
                WorkspaceMapRuntimePaneTab(
                    id: $0.id,
                    title: $0.title,
                    isActive: pane.activeSurfaceID == $0.id
                )
            }
            return .pane(
                WorkspaceMapRuntimePane(
                    id: pane.id,
                    isFocused: pane.activeSurface.id == focusedSurfaceID,
                    tabs: tabs
                )
            )

        case .split(let split):
            return .split(
                direction: split.direction == .horizontal ? .horizontal : .vertical,
                ratio: split.ratio,
                left: makeTerminalNode(split.left, focusedSurfaceID: focusedSurfaceID),
                right: makeTerminalNode(split.right, focusedSurfaceID: focusedSurfaceID)
            )
        }
    }
}
