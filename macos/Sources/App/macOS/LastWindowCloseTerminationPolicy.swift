import AppKit

enum LastClosedTopLevelWindowKind: Equatable {
    case browser
    case terminal
    case other

    static func fromWindowControllerClassName(_ className: String?) -> LastClosedTopLevelWindowKind? {
        guard let className, !className.isEmpty else { return nil }

        switch className {
        case "BrowserTabController", "GhoDexCEFPopupWindowController":
            return .browser
        case "TerminalController":
            return .terminal
        default:
            return .other
        }
    }

    static func resolve(window: NSWindow?) -> LastClosedTopLevelWindowKind? {
        let className = window?.windowController.map { String(describing: type(of: $0)) }
        return fromWindowControllerClassName(className)
    }
}

struct LastWindowCloseTerminationPolicy {
    static func shouldTerminateAfterLastWindowClosed(
        shouldQuitAfterLastWindowClosed: Bool,
        lastClosedWindowKind: LastClosedTopLevelWindowKind?
    ) -> Bool {
        guard shouldQuitAfterLastWindowClosed else { return false }

        switch lastClosedWindowKind {
        case .browser:
            return false
        case .terminal, .other, nil:
            return true
        }
    }
}
