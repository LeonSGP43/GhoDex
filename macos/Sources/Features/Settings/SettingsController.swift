import Cocoa
import SwiftUI

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private unowned let appDelegate: AppDelegate
    private(set) var selectedTab: SettingsView.SettingsTab = .general

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let hostingController = NSHostingController(
            rootView: SettingsView(
                selection: .constant(.general),
                onSelectedTabChange: { _ in }
            ).environmentObject(appDelegate)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppLocalization.localizedText("Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 980, height: 680))

        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(tab: SettingsView.SettingsTab = .general) {
        selectedTab = tab
        guard let window else { return }
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                initialTab: tab,
                selection: Binding(
                    get: { [weak self] in
                        self?.selectedTab ?? tab
                    },
                    set: { [weak self] newValue in
                        self?.selectedTab = newValue
                    }
                ),
                onSelectedTabChange: { [weak self] newValue in
                    self?.selectedTab = newValue
                }
            ).environmentObject(appDelegate)
        )
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func close(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc func cancel(_ sender: Any?) {
        close(sender)
    }
}
