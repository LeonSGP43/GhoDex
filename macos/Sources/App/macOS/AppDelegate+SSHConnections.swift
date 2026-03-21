import AppKit

extension AppDelegate {
    @IBAction func showSSHConnections(_ sender: Any?) {
        sshConnectionsController.show()
    }

    @IBAction func showTodoWorkspace(_ sender: Any?) {
        let preferredWindow = (sender as? NSWindow) ?? NSApp.keyWindow
        let focusedWorkspaceID = activeTodoWorkspaceID(preferred: preferredWindow)
        sshConnectionsController.show(
            tab: .todo,
            todoFocusedWorkspaceID: focusedWorkspaceID,
            tabbedInto: preferredWindow ?? TerminalController.preferredParent?.window
        )
    }

    @MainActor
    func showTodoWorkspace(
        focusedWorkspaceID: UUID?,
        from parentWindow: NSWindow?
    ) {
        sshConnectionsController.show(
            tab: .todo,
            todoFocusedWorkspaceID: focusedWorkspaceID,
            tabbedInto: parentWindow ?? TerminalController.preferredParent?.window
        )
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
}
