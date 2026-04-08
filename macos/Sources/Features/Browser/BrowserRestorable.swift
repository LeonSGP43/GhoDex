import Cocoa

struct BrowserRestorableSnapshot: Codable {
    let workspaceID: UUID
    let urlString: String
    let titleOverride: String?

    init(
        workspaceID: UUID = UUID(),
        urlString: String,
        titleOverride: String?
    ) {
        self.workspaceID = workspaceID
        self.urlString = urlString
        self.titleOverride = titleOverride
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case urlString
        case titleOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID) ?? UUID()
        urlString = try container.decode(String.self, forKey: .urlString)
        titleOverride = try container.decodeIfPresent(String.self, forKey: .titleOverride)
    }
}

@MainActor
protocol BrowserRestorable: Codable {
    static var selfKey: String { get }
    static var versionKey: String { get }
    static var version: Int { get }
    init(copy other: Self)
}

@MainActor
extension BrowserRestorable {
    static var selfKey: String { "state" }
    static var versionKey: String { "version" }

    init?(coder aDecoder: NSCoder) {
        guard aDecoder.decodeInteger(forKey: Self.versionKey) == Self.version else {
            return nil
        }

        guard let value = aDecoder.decodeObject(of: CodableBridge<Self>.self, forKey: Self.selfKey) else {
            return nil
        }

        self.init(copy: value.value)
    }

    func encode(with coder: NSCoder) {
        coder.encode(Self.version, forKey: Self.versionKey)
        coder.encode(CodableBridge(self), forKey: Self.selfKey)
    }
}

@MainActor
final class BrowserRestorableState: BrowserRestorable {
    static let version = 1

    let snapshot: BrowserRestorableSnapshot

    init(from controller: BrowserTabController) {
        self.snapshot = .init(
            workspaceID: controller.workspaceID,
            urlString: controller.model.restorableURL.absoluteString,
            titleOverride: controller.titleOverride)
    }

    init(snapshot: BrowserRestorableSnapshot) {
        self.snapshot = snapshot
    }

    required init(copy other: BrowserRestorableState) {
        self.snapshot = other.snapshot
    }
}

enum BrowserRestoreError: Error {
    case delegateInvalid
    case identifierUnknown
    case stateDecodeFailed
    case windowDidNotLoad
}

@MainActor
final class BrowserWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        guard identifier == .init(String(describing: Self.self)) else {
            completionHandler(nil, BrowserRestoreError.identifierUnknown)
            return
        }

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            completionHandler(nil, BrowserRestoreError.delegateInvalid)
            return
        }

        if appDelegate.ghostty.config.windowSaveState == "never" {
            completionHandler(nil, nil)
            return
        }

        let configuredExternalProfile =
            ProcessInfo.processInfo.environment[BrowserPaths.envProfilePath]
            ?? UserDefaults.standard.string(forKey: BrowserPaths.profileDefaultsKey)
        let isolatedAppSupportRoot = BrowserPaths.isolatedAppSupportRootOverride()
        if !BrowserPaths.shouldRestoreBrowserWindows(
            windowSaveState: appDelegate.ghostty.config.windowSaveState,
            configuredExternalProfile: configuredExternalProfile,
            isolatedAppSupportRootOverride: isolatedAppSupportRoot
        ) {
            // Real external Chrome profiles and isolated Browser roots should
            // not auto-restore previously embedded browser windows. Restoring
            // stale browser pages before the first explicit open can destabilize
            // profile-backed Chromium services and interfere with
            // command-driven control.
            completionHandler(nil, nil)
            return
        }

        guard let state = BrowserRestorableState(coder: state) else {
            completionHandler(nil, BrowserRestoreError.stateDecodeFailed)
            return
        }

        let restoredURL = URL(string: state.snapshot.urlString)
            ?? BrowserTabController.defaultHomePageURL(for: appDelegate.ghostty)
        let controller = BrowserTabController(
            appDelegate.ghostty,
            initialURL: restoredURL,
            workspaceID: state.snapshot.workspaceID
        )
        controller.titleOverride = state.snapshot.titleOverride

        guard let window = controller.window else {
            completionHandler(nil, BrowserRestoreError.windowDidNotLoad)
            return
        }

        completionHandler(window, nil)
    }
}
