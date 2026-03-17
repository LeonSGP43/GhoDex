import AppKit
import SwiftUI

@MainActor
final class NewTabPickerController: NSWindowController {
    private let store: AITerminalManagerStore
    private let theme = GhosttyChromeTheme()
    private let hostingView: NSHostingView<AnyView>
    private var configObserver: NSObjectProtocol?
    private weak var referenceWindow: NSWindow?
    private var presentationID = UUID()

    init(store: AITerminalManagerStore) {
        self.store = store
        self.hostingView = NSHostingView(rootView: AnyView(EmptyView()))

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
        window.contentView = hostingView

        super.init(window: window)
        hostingView.rootView = makeRootView()

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

    func show(
        relativeTo parentWindow: NSWindow?,
        title: String = L10n.AITerminalManager.newTab,
        subtitle: String = L10n.SSHConnections.newTabPickerSubtitle,
        onOpenHost: ((AITerminalHost) -> Void)? = nil
    ) {
        store.refresh()
        referenceWindow = parentWindow
        presentationID = UUID()
        hostingView.rootView = makeRootView(
            title: title,
            subtitle: subtitle,
            onOpenHost: onOpenHost)
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

    private func makeRootView(
        title: String = L10n.AITerminalManager.newTab,
        subtitle: String = L10n.SSHConnections.newTabPickerSubtitle,
        onOpenHost: ((AITerminalHost) -> Void)? = nil
    ) -> AnyView {
        AnyView(
            NewTabPickerView(
                title: title,
                subtitle: subtitle,
                onClose: { [weak self] in
                    guard let window = self?.window else { return }
                    if let sheetParent = window.sheetParent {
                        sheetParent.endSheet(window)
                    } else {
                        window.close()
                    }
                },
                onOpenHost: onOpenHost
            )
            .id(presentationID)
            .environmentObject(store)
            .environmentObject(theme)
        )
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
