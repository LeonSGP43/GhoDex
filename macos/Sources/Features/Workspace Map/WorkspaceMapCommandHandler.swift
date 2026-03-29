import AppKit

@MainActor
protocol WorkspaceMapCommandGateway {
    func focusTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult
    func renameTopLevelGroup(_ targetID: WorkspaceMapEntityID, title: String?) -> WorkspaceMapCommandResult
    func closeTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult
    func jumpToTerminalPaneTab(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult
}

@MainActor
struct WorkspaceMapRuntimeCommandGateway: WorkspaceMapCommandGateway {
    func focusTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        guard let controller = topLevelController(for: targetID) else {
            return WorkspaceMapCommandResult(
                status: .targetNotFound,
                message: "Top-level group \(targetID.rawValue) was not found."
            )
        }

        activate(controller)
        return WorkspaceMapCommandResult(
            status: .executed,
            message: "Focused \(targetID.rawValue)."
        )
    }

    func renameTopLevelGroup(
        _ targetID: WorkspaceMapEntityID,
        title: String?
    ) -> WorkspaceMapCommandResult {
        guard let controller = topLevelController(for: targetID) else {
            return WorkspaceMapCommandResult(
                status: .targetNotFound,
                message: "Top-level group \(targetID.rawValue) was not found."
            )
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTitle, !normalizedTitle.isEmpty {
            controller.titleOverride = normalizedTitle
        } else {
            controller.promptTabTitle()
        }

        activate(controller)
        return WorkspaceMapCommandResult(
            status: .executed,
            message: "Rename command applied to \(targetID.rawValue)."
        )
    }

    func closeTopLevelGroup(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        guard let controller = topLevelController(for: targetID) else {
            return WorkspaceMapCommandResult(
                status: .targetNotFound,
                message: "Top-level group \(targetID.rawValue) was not found."
            )
        }

        controller.closeTabImmediately(registerRedo: true)
        return WorkspaceMapCommandResult(
            status: .executed,
            message: "Closed \(targetID.rawValue)."
        )
    }

    func jumpToTerminalPaneTab(_ targetID: WorkspaceMapEntityID) -> WorkspaceMapCommandResult {
        guard let paneTabID = targetID.paneTabUUID else {
            return WorkspaceMapCommandResult(
                status: .invalidRequest,
                message: "jumpToTerminalPaneTab requires a pane-tab target ID."
            )
        }

        for controller in TerminalController.all {
            guard let pane = controller.surfaceTree.first(where: { pane in
                pane.surfaces.contains(where: { $0.id == paneTabID })
            }) else {
                continue
            }

            controller.selectPaneTab(paneTabID, in: pane)
            controller.focusPane(pane)
            activate(controller)
            return WorkspaceMapCommandResult(
                status: .executed,
                message: "Jumped to pane-tab \(paneTabID.uuidString.lowercased())."
            )
        }

        return WorkspaceMapCommandResult(
            status: .targetNotFound,
            message: "Pane-tab \(paneTabID.uuidString.lowercased()) was not found."
        )
    }

    private func topLevelController(for groupID: WorkspaceMapEntityID) -> TopLevelTabController? {
        if let workspaceID = groupID.terminalGroupUUID {
            return TerminalController.all.first {
                WorkspaceMapEntityID.terminalGroup($0.workspaceID) == groupID
                    && $0.workspaceID == workspaceID
            }
        }

        if let browserWorkspaceID = groupID.browserGroupUUID {
            return BrowserTabController.lookup(workspaceID: browserWorkspaceID)
        }

        if let externalID = groupID.browserGroupExternalID {
            return BrowserTabController.lookup(externalID: externalID)
        }

        return nil
    }

    private func activate(_ controller: TopLevelTabController) {
        (controller as? NSWindowController)?.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum WorkspaceMapCommandHandler {
    static func execute(
        _ request: WorkspaceMapCommandRequest,
        gateway: WorkspaceMapCommandGateway? = nil
    ) -> WorkspaceMapCommandResult {
        guard WorkspaceMapCommandPolicy.isAllowedInV1(request.command) else {
            return WorkspaceMapCommandResult(
                status: .blockedByPolicy,
                message: "Command \(request.command.rawValue) is blocked by Workspace Map v1 policy."
            )
        }

        let gateway = gateway ?? WorkspaceMapRuntimeCommandGateway()

        switch request.command {
        case .focusTopLevelGroup:
            return gateway.focusTopLevelGroup(request.targetID)

        case .renameTopLevelGroup:
            return gateway.renameTopLevelGroup(request.targetID, title: request.title)

        case .closeTopLevelGroup:
            return gateway.closeTopLevelGroup(request.targetID)

        case .jumpToTerminalPaneTab:
            guard request.targetID.paneTabUUID != nil else {
                return WorkspaceMapCommandResult(
                    status: .invalidRequest,
                    message: "jumpToTerminalPaneTab requires a pane-tab target ID."
                )
            }
            return gateway.jumpToTerminalPaneTab(request.targetID)

        case .editSplitTree:
            return WorkspaceMapCommandResult(
                status: .blockedByPolicy,
                message: "Split-tree editing is disabled in Workspace Map v1."
            )
        }
    }
}
