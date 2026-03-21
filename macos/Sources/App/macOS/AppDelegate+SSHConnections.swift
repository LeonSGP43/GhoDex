import AppKit

extension AppDelegate {
    @IBAction func showSSHConnections(_ sender: Any?) {
        sshConnectionsController.show()
    }

    @IBAction func showTodoWorkspace(_ sender: Any?) {
        let preferredWindow = (sender as? NSWindow) ?? NSApp.keyWindow
        if toggleTodoSidebar(from: preferredWindow) {
            return
        }
        openTodoSettings(from: preferredWindow)
    }

    @MainActor
    @discardableResult
    func toggleTodoSidebar(
        focusedWorkspaceID: UUID? = nil,
        from parentWindow: NSWindow?
    ) -> Bool {
        guard let controller = activeTodoTerminalController(preferred: parentWindow) else {
            return false
        }

        if let focusedWorkspaceID,
           controller.workspaceID != focusedWorkspaceID {
            controller.todoSidebarIsPresented = false
            guard let targetController = TerminalController.all.first(where: { $0.workspaceID == focusedWorkspaceID }) else {
                return false
            }
            targetController.todoSidebarIsPresented.toggle()
            targetController.window?.makeKeyAndOrderFront(nil)
        } else {
            controller.todoSidebarIsPresented.toggle()
            controller.window?.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @MainActor
    func openTodoSettings(from parentWindow: NSWindow?) {
        let focusedWorkspaceID = activeTodoWorkspaceID(preferred: parentWindow)
        sshConnectionsController.show(
            tab: .todo,
            todoFocusedWorkspaceID: focusedWorkspaceID,
            tabbedInto: parentWindow ?? TerminalController.preferredParent?.window
        )
    }

    @MainActor
    func showTodoWorkspace(
        focusedWorkspaceID: UUID?,
        from parentWindow: NSWindow?
    ) {
        if toggleTodoSidebar(focusedWorkspaceID: focusedWorkspaceID, from: parentWindow) {
            return
        }
        openTodoSettings(from: parentWindow)
    }

    @MainActor
    private func activeTodoWorkspaceID(preferred window: NSWindow? = nil) -> UUID? {
        [
            window,
            NSApp.keyWindow,
            NSApp.mainWindow,
            TerminalController.preferredParent?.window,
        ]
        .compactMap { candidate in
            let selectedWindow = candidate?.tabGroup?.selectedWindow ?? candidate
            return (selectedWindow?.windowController as? TerminalController)?.workspaceID
        }
        .first
    }

    @MainActor
    private func activeTodoTerminalController(preferred window: NSWindow? = nil) -> BaseTerminalController? {
        [
            window,
            NSApp.keyWindow,
            NSApp.mainWindow,
            TerminalController.preferredParent?.window,
        ]
        .compactMap { candidate in
            let selectedWindow = candidate?.tabGroup?.selectedWindow ?? candidate
            return selectedWindow?.windowController as? BaseTerminalController
        }
        .first
    }
}
