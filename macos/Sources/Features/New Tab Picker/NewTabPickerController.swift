import AppKit
import SwiftUI

@MainActor
final class NewTabPickerController: NSWindowController {
    private let store: AITerminalManagerStore
    private let theme = GhosttyChromeTheme()
    private var configObserver: NSObjectProtocol?
    private weak var referenceWindow: NSWindow?

    init(store: AITerminalManagerStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.minSize = NSSize(width: 560, height: 460)
        window.contentView = NSHostingView(
            rootView: NewTabPickerView(onClose: { [weak window] in
                if let sheetParent = window?.sheetParent, let window {
                    sheetParent.endSheet(window)
                } else {
                    window?.close()
                }
            })
            .environmentObject(store)
            .environmentObject(theme)
        )

        super.init(window: window)

        configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncChrome()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for NewTabPickerController")
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    func show(relativeTo parentWindow: NSWindow?) {
        store.refresh()
        referenceWindow = parentWindow
        syncChrome()

        guard let window else { return }

        if let parentWindow, parentWindow.attachedSheet !== window {
            if let currentParent = window.sheetParent, currentParent !== parentWindow {
                currentParent.endSheet(window)
            }

            if parentWindow.attachedSheet == nil {
                parentWindow.beginSheet(window)
                return
            }
        }

        showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncChrome() {
        let appDelegate = NSApp.delegate as? AppDelegate
        let backgroundColor = GhosttyChrome.resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
        theme.apply(backgroundColor: backgroundColor)
        GhosttyChrome.syncWindowAppearance(
            window,
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
    }
}
