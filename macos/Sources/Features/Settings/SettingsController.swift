import Cocoa
import SwiftUI

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private unowned let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let hostingController = NSHostingController(
            rootView: SettingsView().environmentObject(appDelegate)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppLocalization.localizedText("Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 520, height: 320))

        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(appDelegate)
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
