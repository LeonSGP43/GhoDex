import Cocoa

enum TerminalWorkspaceSwitcherMode: String, Codable {
    case top
    case sidebar
}

struct TerminalWorkspaceSnapshot: Codable {
    let id: UUID
    let title: String?
    let surfaceTree: SplitTree<TerminalPane>
    let focusedSurfaceID: UUID?
    let effectiveFullscreenMode: FullscreenMode?
    let tabColor: TerminalTabColor
    let switcherMode: TerminalWorkspaceSwitcherMode

    init(
        id: UUID = UUID(),
        title: String? = nil,
        surfaceTree: SplitTree<TerminalPane>,
        focusedSurfaceID: UUID? = nil,
        effectiveFullscreenMode: FullscreenMode? = nil,
        tabColor: TerminalTabColor = .none,
        switcherMode: TerminalWorkspaceSwitcherMode = .top
    ) {
        self.id = id
        self.title = title
        self.surfaceTree = surfaceTree
        self.focusedSurfaceID = focusedSurfaceID
        self.effectiveFullscreenMode = effectiveFullscreenMode
        self.tabColor = tabColor
        self.switcherMode = switcherMode
    }

    var focusedSurface: String? { focusedSurfaceID?.uuidString }
    var titleOverride: String? { title }
}

protocol TerminalRestorable: Codable {
    static var selfKey: String { get }
    static var versionKey: String { get }
    static var version: Int { get }
    init(copy other: Self)

    /// Returns a base configuration to use when restoring terminal surfaces.
    /// Override this to provide custom environment variables or other configuration.
    var baseConfig: Ghostty.SurfaceConfiguration? { get }
}

extension TerminalRestorable {
    static var selfKey: String { "state" }
    static var versionKey: String { "version" }

    /// Default implementation returns nil (no custom base config).
    var baseConfig: Ghostty.SurfaceConfiguration? { nil }

    init?(coder aDecoder: NSCoder) {
        // If the version doesn't match then we can't decode. In the future we can perform
        // version upgrading or something but for now we only have one version so we
        // don't bother.
        guard aDecoder.decodeInteger(forKey: Self.versionKey) == Self.version else {
            return nil
        }

        guard let v = aDecoder.decodeObject(of: CodableBridge<Self>.self, forKey: Self.selfKey) else {
            return nil
        }

        self.init(copy: v.value)
    }

    func encode(with coder: NSCoder) {
        coder.encode(Self.version, forKey: Self.versionKey)
        coder.encode(CodableBridge(self), forKey: Self.selfKey)
    }
}

/// The state stored for terminal window restoration.
class TerminalRestorableState: TerminalRestorable {
    class var version: Int { 9 }

    let workspace: TerminalWorkspaceSnapshot

    var focusedSurface: String? { workspace.focusedSurface }
    var surfaceTree: SplitTree<TerminalPane> { workspace.surfaceTree }
    var effectiveFullscreenMode: FullscreenMode? { workspace.effectiveFullscreenMode }
    var tabColor: TerminalTabColor { workspace.tabColor }
    var titleOverride: String? { workspace.titleOverride }

    init(from controller: TerminalController) {
        self.workspace = controller.makeWorkspaceSnapshot()
    }

    init(workspace: TerminalWorkspaceSnapshot) {
        self.workspace = workspace
    }

    required init(copy other: TerminalRestorableState) {
        self.workspace = other.workspace
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case focusedSurface
        case surfaceTree
        case effectiveFullscreenMode
        case tabColor
        case titleOverride
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let workspace = try container.decodeIfPresent(TerminalWorkspaceSnapshot.self, forKey: .workspace) {
            self.workspace = workspace
            return
        }

        let focusedSurfaceID = try container.decodeIfPresent(String.self, forKey: .focusedSurface)
            .flatMap(UUID.init(uuidString:))
        self.workspace = .init(
            title: try container.decodeIfPresent(String.self, forKey: .titleOverride),
            surfaceTree: try container.decode(SplitTree<TerminalPane>.self, forKey: .surfaceTree),
            focusedSurfaceID: focusedSurfaceID,
            effectiveFullscreenMode: try container.decodeIfPresent(FullscreenMode.self, forKey: .effectiveFullscreenMode),
            tabColor: try container.decode(TerminalTabColor.self, forKey: .tabColor))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspace, forKey: .workspace)
    }
}

enum TerminalRestoreError: Error {
    case delegateInvalid
    case identifierUnknown
    case stateDecodeFailed
    case windowDidNotLoad
}

/// The NSWindowRestoration implementation that is called when a terminal window needs to be restored.
/// The encoding of a terminal window is handled elsewhere (usually NSWindowDelegate).
class TerminalWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        // Verify the identifier is what we expect
        guard identifier == .init(String(describing: Self.self)) else {
            completionHandler(nil, TerminalRestoreError.identifierUnknown)
            return
        }

        // The app delegate is definitely setup by now. If it isn't our AppDelegate
        // then something is royally fucked up but protect against it anyhow.
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            completionHandler(nil, TerminalRestoreError.delegateInvalid)
            return
        }

        // If our configuration is "never" then we never restore the state
        // no matter what. Note its safe to use "ghostty.config" directly here
        // because window restoration is only ever invoked on app start so we
        // don't have to deal with config reloads.
        if appDelegate.ghostty.config.windowSaveState == "never" {
            completionHandler(nil, nil)
            return
        }

        // Decode the state. If we can't decode the state, then we can't restore.
        guard let state = TerminalRestorableState(coder: state) else {
            completionHandler(nil, TerminalRestoreError.stateDecodeFailed)
            return
        }

        // The window creation has to go through our terminalManager so that it
        // can be found for events from libghostty. This uses the low-level
        // createWindow so that AppKit can place the window wherever it should
        // be.
        let c = TerminalController(
            appDelegate.ghostty,
            workspaceSnapshot: state.workspace)
        guard let window = c.window else {
            completionHandler(nil, TerminalRestoreError.windowDidNotLoad)
            return
        }

        // Restore our tab color
        (window as? TerminalWindow)?.tabColor = state.tabColor

        // Setup our restored state on the controller.
        if let focusedStr = state.focusedSurface {
            var foundView: Ghostty.SurfaceView?
            for view in c.allSurfaces where view.id.uuidString == focusedStr {
                foundView = view
                break
            }

            if let view = foundView {
                c.focusedSurface = view
                restoreFocus(to: view, inWindow: window)
            }
        }

        completionHandler(window, nil)
        guard let mode = state.effectiveFullscreenMode, mode != .native else {
            // We let AppKit handle native fullscreen
            return
        }
        // Give the window to AppKit first, then adjust its frame and style
        // to minimise any visible frame changes.
        c.toggleFullscreen(mode: mode)
    }

    /// This restores the focus state of the surfaceview within the given window. When restoring,
    /// the view isn't immediately attached to the window since we have to wait for SwiftUI to
    /// catch up. Therefore, we sit in an async loop waiting for the attachment to happen.
    private static func restoreFocus(to: Ghostty.SurfaceView, inWindow: NSWindow, attempts: Int = 0) {
        // For the first attempt, we schedule it immediately. Subsequent events wait a bit
        // so we don't just spin the CPU at 100%. Give up after some period of time.
        let after: DispatchTime
        if attempts == 0 {
            after = .now()
        } else if attempts > 40 {
            // 2 seconds, give up
            return
        } else {
            after = .now() + .milliseconds(50)
        }

        DispatchQueue.main.asyncAfter(deadline: after) {
            // If the view is not attached to a window yet then we repeat.
            guard let viewWindow = to.window else {
                restoreFocus(to: to, inWindow: inWindow, attempts: attempts + 1)
                return
            }

            // If the view is attached to some other window, we give up
            guard viewWindow == inWindow else { return }

            inWindow.makeFirstResponder(to)

            // If the window is main, then we also make sure it comes forward. This
            // prevents a bug found in #1177 where sometimes on restore the windows
            // would be behind other applications.
            if viewWindow.isMainWindow {
                viewWindow.orderFront(nil)
            }
        }
    }
}
