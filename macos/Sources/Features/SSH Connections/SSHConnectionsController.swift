import Cocoa
import SwiftUI

enum SSHConnectionsPanelTab: String, CaseIterable, Identifiable {
    case connections
    case learning
    case taskQueue
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connections:
            return L10n.SSHConnections.tabConnections
        case .learning:
            return L10n.SSHConnections.tabLearning
        case .taskQueue:
            return "Task Queue"
        case .preferences:
            return L10n.Settings.title
        }
    }
}

@MainActor
final class SSHConnectionsPresentationState: ObservableObject {
    @Published var selectedTab: SSHConnectionsPanelTab = .connections
}

final class SSHConnectionsController: NSWindowController, NSWindowDelegate {
    private let store: AITerminalManagerStore
    private let presentationState = SSHConnectionsPresentationState()

    static func windowsAreInSameTabGroup(_ lhs: NSWindow?, _ rhs: NSWindow?) -> Bool {
        guard
            let lhsGroup = lhs?.tabGroup,
            let rhsGroup = rhs?.tabGroup
        else { return false }

        return lhsGroup === rhsGroup
    }

    init(appDelegate: AppDelegate, store: AITerminalManagerStore) {
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
            rootView: SSHConnectionsView(presentation: presentationState)
                .environmentObject(store)
                .environmentObject(appDelegate)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SSHConnectionsController")
    }

    func show(
        tab selectedTab: SSHConnectionsPanelTab = .connections,
        tabbedInto parentWindow: NSWindow? = TerminalController.preferredParent?.window
    ) {
        presentationState.selectedTab = selectedTab
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
