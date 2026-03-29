import Foundation

enum WorkspaceMapProjectionService {
    private struct ProjectionStrings {
        let paneTitle: String
        let splitTitle: String

        static func resolve() -> Self {
            Self(
                paneTitle: AppLocalization.localizedText("Pane"),
                splitTitle: AppLocalization.localizedText("Split")
            )
        }
    }

    private struct TerminalHierarchyProjection {
        let rootID: WorkspaceMapEntityID?
        let nodes: [WorkspaceMapNodeSnapshot]
        let splitCount: Int
        let paneCount: Int
        let tabCount: Int
        let hasFocusedPane: Bool

        static let empty = TerminalHierarchyProjection(
            rootID: nil,
            nodes: [],
            splitCount: 0,
            paneCount: 0,
            tabCount: 0,
            hasFocusedPane: false
        )
    }

    private struct TerminalHierarchyMeta {
        let rootID: WorkspaceMapEntityID?
        let splitCount: Int
        let paneCount: Int
        let tabCount: Int
        let hasFocusedPane: Bool

        static let empty = TerminalHierarchyMeta(
            rootID: nil,
            splitCount: 0,
            paneCount: 0,
            tabCount: 0,
            hasFocusedPane: false
        )
    }

    @MainActor
    static func makeSnapshot(now: Date = Date()) -> WorkspaceMapSnapshot {
        makeSnapshot(
            from: WorkspaceMapRuntimeAdapter.capture(),
            now: now
        )
    }

    static func makeSnapshot(
        from runtimeState: WorkspaceMapRuntimeState,
        now: Date = Date()
    ) -> WorkspaceMapSnapshot {
        let strings = ProjectionStrings.resolve()
        let terminalGroups = runtimeState.terminalGroups.map { makeTerminalGroupSnapshot($0, strings: strings) }
        let browserGroups = runtimeState.browserGroups.map(makeBrowserGroupSnapshot)
        let groups = (terminalGroups + browserGroups).sorted(by: groupSortKey)
        return WorkspaceMapSnapshot(generatedAt: now, groups: groups)
    }

    private static func makeTerminalGroupSnapshot(
        _ group: WorkspaceMapRuntimeTerminalGroup,
        strings: ProjectionStrings
    ) -> WorkspaceMapGroupSnapshot {
        let groupID = WorkspaceMapEntityID.terminalGroup(group.workspaceID)
        let projection = projectTerminalHierarchy(group.root, groupID: groupID, strings: strings)

        return WorkspaceMapGroupSnapshot(
            id: groupID,
            kind: .terminal,
            title: group.title,
            isFocused: group.isFocused,
            terminal: WorkspaceMapTerminalGroupSnapshot(
                rootNodeID: projection.rootID,
                splitCount: projection.splitCount,
                paneCount: projection.paneCount,
                tabCount: projection.tabCount,
                nodes: projection.nodes
            ),
            browser: nil
        )
    }

    private static func makeBrowserGroupSnapshot(
        _ group: WorkspaceMapRuntimeBrowserGroup
    ) -> WorkspaceMapGroupSnapshot {
        WorkspaceMapGroupSnapshot(
            id: .browserGroup(group.workspaceID),
            kind: .browser,
            title: group.title,
            isFocused: group.isFocused,
            terminal: nil,
            browser: WorkspaceMapBrowserGroupSnapshot(
                selectedPageID: group.selectedPageID,
                displayedURL: group.displayedURL
            )
        )
    }

    private static func groupSortKey(
        _ lhs: WorkspaceMapGroupSnapshot,
        _ rhs: WorkspaceMapGroupSnapshot
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }

        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func projectTerminalHierarchy(
        _ root: WorkspaceMapRuntimeTerminalNode?,
        groupID: WorkspaceMapEntityID,
        strings: ProjectionStrings
    ) -> TerminalHierarchyProjection {
        guard let root else { return .empty }
        var nodes: [WorkspaceMapNodeSnapshot] = []
        let meta = projectTerminalNode(
            root,
            parentID: nil,
            path: [],
            groupID: groupID,
            strings: strings,
            nodes: &nodes
        )
        return TerminalHierarchyProjection(
            rootID: meta.rootID,
            nodes: nodes,
            splitCount: meta.splitCount,
            paneCount: meta.paneCount,
            tabCount: meta.tabCount,
            hasFocusedPane: meta.hasFocusedPane
        )
    }

    private static func projectTerminalNode(
        _ node: WorkspaceMapRuntimeTerminalNode,
        parentID: WorkspaceMapEntityID?,
        path: [WorkspaceMapSplitBranch],
        groupID: WorkspaceMapEntityID,
        strings: ProjectionStrings,
        nodes: inout [WorkspaceMapNodeSnapshot]
    ) -> TerminalHierarchyMeta {
        switch node {
        case .pane(let pane):
            let paneID = WorkspaceMapEntityID.pane(pane.id)

            var paneTabIDs: [WorkspaceMapEntityID] = []
            let paneSnapshot = WorkspaceMapNodeSnapshot(
                id: paneID,
                kind: .pane,
                title: strings.paneTitle,
                parentID: parentID,
                isActive: pane.isFocused,
                childIDs: pane.tabs.map { WorkspaceMapEntityID.paneTab($0.id) }
            )
            nodes.append(paneSnapshot)
            for paneTab in pane.tabs {
                let paneTabSnapshot = makePaneTabNodeSnapshot(paneTab, parentID: paneID)
                paneTabIDs.append(paneTabSnapshot.id)
                nodes.append(paneTabSnapshot)
            }
            return TerminalHierarchyMeta(
                rootID: paneID,
                splitCount: 0,
                paneCount: 1,
                tabCount: paneTabIDs.count,
                hasFocusedPane: pane.isFocused
            )

        case .split(let direction, let ratio, let left, let right):
            let splitID = WorkspaceMapEntityID.split(groupID: groupID, path: path)
            let splitIndex = nodes.count
            nodes.append(
                WorkspaceMapNodeSnapshot(
                    id: splitID,
                    kind: .split,
                    title: strings.splitTitle,
                    parentID: parentID,
                    isActive: false,
                    childIDs: [],
                    splitDirection: direction,
                    splitRatio: ratio
                )
            )

            let leftProjection = projectTerminalNode(
                left,
                parentID: splitID,
                path: path + [.left],
                groupID: groupID,
                strings: strings,
                nodes: &nodes
            )
            let rightProjection = projectTerminalNode(
                right,
                parentID: splitID,
                path: path + [.right],
                groupID: groupID,
                strings: strings,
                nodes: &nodes
            )
            let childIDs = [leftProjection.rootID, rightProjection.rootID].compactMap { $0 }

            nodes[splitIndex] = WorkspaceMapNodeSnapshot(
                id: splitID,
                kind: .split,
                title: strings.splitTitle,
                parentID: parentID,
                isActive: leftProjection.hasFocusedPane || rightProjection.hasFocusedPane,
                childIDs: childIDs,
                splitDirection: direction,
                splitRatio: ratio
            )
            return TerminalHierarchyMeta(
                rootID: splitID,
                splitCount: 1 + leftProjection.splitCount + rightProjection.splitCount,
                paneCount: leftProjection.paneCount + rightProjection.paneCount,
                tabCount: leftProjection.tabCount + rightProjection.tabCount,
                hasFocusedPane: leftProjection.hasFocusedPane || rightProjection.hasFocusedPane
            )
        }
    }

    private static func makePaneTabNodeSnapshot(
        _ paneTab: WorkspaceMapRuntimePaneTab,
        parentID: WorkspaceMapEntityID
    ) -> WorkspaceMapNodeSnapshot {
        WorkspaceMapNodeSnapshot(
            id: .paneTab(paneTab.id),
            kind: .paneTab,
            title: paneTab.title,
            parentID: parentID,
            isActive: paneTab.isActive
        )
    }
}
