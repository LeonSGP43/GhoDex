import AppKit

extension AppDelegate {
    @IBAction func showSSHConnections(_ sender: Any?) {
        let selectedTab: SSHConnectionsPanelTab
        if let menuItem = sender as? NSMenuItem,
           isSettingsPanelMenuItem(menuItem) {
            selectedTab = .preferences
        } else {
            selectedTab = .connections
        }

        sshConnectionsController.show(tab: selectedTab)
    }

    private func isSettingsPanelMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let title = menuItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Settings Panel…",
            "设置面板…",
            AppLocalization.localizedText("Settings Panel…"),
        ].contains(title)
    }
}
