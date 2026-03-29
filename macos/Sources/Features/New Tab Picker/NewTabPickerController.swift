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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
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
        window.minSize = NSSize(width: 760, height: 560)
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
        mode: NewTabPickerMode = .topLevel,
        title: String = L10n.AITerminalManager.newTab,
        subtitle: String = L10n.SSHConnections.newTabPickerSubtitle,
        includeBrowserEntry: Bool = true,
        onOpenHost: ((AITerminalHost) -> Void)? = nil,
        onOpenBrowser: (() -> Void)? = nil,
        onOpenWorkspaceMap: (() -> Void)? = nil,
        onOpenWorkspace: ((AITerminalSavedWorkspaceTemplate) -> Void)? = nil
    ) {
        store.refresh()
        referenceWindow = parentWindow
        presentationID = UUID()
        hostingView.rootView = makeRootView(
            mode: mode,
            title: title,
            subtitle: subtitle,
            includeBrowserEntry: includeBrowserEntry,
            onOpenHost: onOpenHost,
            onOpenBrowser: onOpenBrowser,
            onOpenWorkspaceMap: onOpenWorkspaceMap,
            onOpenWorkspace: onOpenWorkspace
        )
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
        mode: NewTabPickerMode = .topLevel,
        title: String = L10n.AITerminalManager.newTab,
        subtitle: String = L10n.SSHConnections.newTabPickerSubtitle,
        includeBrowserEntry: Bool = true,
        onOpenHost: ((AITerminalHost) -> Void)? = nil,
        onOpenBrowser: (() -> Void)? = nil,
        onOpenWorkspaceMap: (() -> Void)? = nil,
        onOpenWorkspace: ((AITerminalSavedWorkspaceTemplate) -> Void)? = nil
    ) -> AnyView {
        AnyView(
            NewTabPickerView(
                mode: mode,
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
                includeBrowserEntry: includeBrowserEntry,
                onOpenHost: onOpenHost,
                onOpenBrowser: onOpenBrowser,
                onOpenWorkspaceMap: onOpenWorkspaceMap,
                onOpenWorkspace: onOpenWorkspace
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
