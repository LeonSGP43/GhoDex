import Cocoa
import SwiftUI

final class SSHConnectionsController: NSWindowController, NSWindowDelegate {
    private let store: AITerminalManagerStore

    static func windowsAreInSameTabGroup(_ lhs: NSWindow?, _ rhs: NSWindow?) -> Bool {
        guard
            let lhsGroup = lhs?.tabGroup,
            let rhsGroup = rhs?.tabGroup
        else { return false }

        return lhsGroup === rhsGroup
    }

    init(store: AITerminalManagerStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.SSHConnections.windowTitle
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1280, height: 760)
        window.tabbingMode = .preferred
        DispatchQueue.main.async {
            window.tabbingMode = .automatic
        }
        window.center()
        window.contentView = NSHostingView(
            rootView: SSHConnectionsView()
                .environmentObject(store)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SSHConnectionsController")
    }

    func show(tabbedInto parentWindow: NSWindow? = TerminalController.preferredParent?.window) {
        store.refresh()

        if let window,
           let parentWindow,
           parentWindow !== window {
            if parentWindow.isMiniaturized {
                parentWindow.deminiaturize(nil)
            }

            let sameTabGroup = Self.windowsAreInSameTabGroup(window, parentWindow)
            if !sameTabGroup &&
                parentWindow.tabbingMode != .disallowed &&
                window.tabbingMode != .disallowed {
                _ = parentWindow.addTabbedWindowSafely(window, ordered: .above)
            }
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
