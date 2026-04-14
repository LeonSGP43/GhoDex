import AppKit
import CoreImage
import SwiftUI
import UserNotifications
import OSLog
import Sparkle
import GhoDexKit
import Darwin
import UniformTypeIdentifiers

enum RemotePairingQRCodeRequestSource: Equatable {
    case manual
    case launchPreference
}

enum RemotePairingQRCodeErrorPresentation: Equatable {
    case blockingModal
    case logOnly
}

struct RemotePairingQRCodePresentationPolicy {
    static func errorPresentation(
        for source: RemotePairingQRCodeRequestSource
    ) -> RemotePairingQRCodeErrorPresentation {
        switch source {
        case .manual:
            return .blockingModal
        case .launchPreference:
            return .logOnly
        }
    }
}

class AppDelegate: NSObject,
                    ObservableObject,
                    NSApplicationDelegate,
                    UNUserNotificationCenterDelegate,
                    GhosttyAppDelegate {
    struct RelaunchProcessPlan: Equatable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]?
        let currentDirectoryURL: URL?
    }

    private static let skipInitialTerminalWindowEnvKey = "GHODEX_SKIP_INITIAL_TERMINAL_WINDOW"
    private static let isRunningUnderTests = isRunningTests()
    private static let controlHarnessANSIEscapeRegex = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
    )
    // The application logger. We should probably move this at some point to a dedicated
    // class/struct but for now it lives here! 🤷‍♂️
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    /// Various menu items so that we can programmatically sync the keyboard shortcut with the Ghostty config
    @IBOutlet private var menuAbout: NSMenuItem?
    @IBOutlet private var menuServices: NSMenu?
    @IBOutlet private var menuCheckForUpdates: NSMenuItem?
    @IBOutlet private var menuOpenConfig: NSMenuItem?
    @IBOutlet private var menuSettingsPanel: NSMenuItem?
    private var menuTodoWorkspace: NSMenuItem?
    @IBOutlet private var menuReloadConfig: NSMenuItem?
    @IBOutlet private var menuSecureInput: NSMenuItem?
    @IBOutlet private var menuQuit: NSMenuItem?

    @IBOutlet private var menuNewWindow: NSMenuItem?
    @IBOutlet private var menuNewTab: NSMenuItem?
    @IBOutlet private var menuSaveWorkspace: NSMenuItem?
    @IBOutlet private var menuSplitRight: NSMenuItem?
    @IBOutlet private var menuSplitLeft: NSMenuItem?
    @IBOutlet private var menuSplitDown: NSMenuItem?
    @IBOutlet private var menuSplitUp: NSMenuItem?
    @IBOutlet private var menuClose: NSMenuItem?
    @IBOutlet private var menuCloseTab: NSMenuItem?
    @IBOutlet private var menuCloseWindow: NSMenuItem?
    @IBOutlet private var menuCloseAllWindows: NSMenuItem?

    @IBOutlet private var menuUndo: NSMenuItem?
    @IBOutlet private var menuRedo: NSMenuItem?
    @IBOutlet private var menuCopy: NSMenuItem?
    @IBOutlet private var menuPaste: NSMenuItem?
    @IBOutlet private var menuPasteSelection: NSMenuItem?
    @IBOutlet private var menuSelectAll: NSMenuItem?
    @IBOutlet private var menuFindParent: NSMenuItem?
    @IBOutlet private var menuFind: NSMenuItem?
    @IBOutlet private var menuSelectionForFind: NSMenuItem?
    @IBOutlet private var menuScrollToSelection: NSMenuItem?
    @IBOutlet private var menuFindNext: NSMenuItem?
    @IBOutlet private var menuFindPrevious: NSMenuItem?
    @IBOutlet private var menuHideFindBar: NSMenuItem?

    @IBOutlet private var menuToggleVisibility: NSMenuItem?
    @IBOutlet private var menuToggleFullScreen: NSMenuItem?
    @IBOutlet private var menuBringAllToFront: NSMenuItem?
    @IBOutlet private var menuZoomSplit: NSMenuItem?
    @IBOutlet private var menuPreviousSplit: NSMenuItem?
    @IBOutlet private var menuNextSplit: NSMenuItem?
    @IBOutlet private var menuSelectSplitAbove: NSMenuItem?
    @IBOutlet private var menuSelectSplitBelow: NSMenuItem?
    @IBOutlet private var menuSelectSplitLeft: NSMenuItem?
    @IBOutlet private var menuSelectSplitRight: NSMenuItem?
    @IBOutlet private var menuReturnToDefaultSize: NSMenuItem?
    @IBOutlet private var menuFloatOnTop: NSMenuItem?
    @IBOutlet private var menuUseAsDefault: NSMenuItem?
    @IBOutlet private var menuSetAsDefaultTerminal: NSMenuItem?

    @IBOutlet private var menuIncreaseFontSize: NSMenuItem?
    @IBOutlet private var menuDecreaseFontSize: NSMenuItem?
    @IBOutlet private var menuResetFontSize: NSMenuItem?
    @IBOutlet private var menuChangeTitle: NSMenuItem?
    @IBOutlet private var menuChangeTabTitle: NSMenuItem?
    @IBOutlet private var menuReadonly: NSMenuItem?
    @IBOutlet private var menuQuickTerminal: NSMenuItem?
    @IBOutlet private var menuTerminalInspector: NSMenuItem?
    @IBOutlet private var menuCommandPalette: NSMenuItem?

    @IBOutlet private var menuEqualizeSplits: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerUp: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerDown: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerLeft: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerRight: NSMenuItem?

    /// The dock menu
    private var dockMenu: NSMenu = NSMenu()

    /// This is only true before application has become active.
    private var applicationHasBecomeActive: Bool = false

    /// This is set in applicationDidFinishLaunching with the system uptime so we can determine the
    /// seconds since the process was launched.
    private var applicationLaunchTime: TimeInterval = 0

    /// This is the current configuration from the Ghostty configuration that we need.
    private var derivedConfig: DerivedConfig = DerivedConfig()

    static func shouldSkipInitialTerminalWindow(environment: [String: String]) -> Bool {
        guard let rawValue = environment[skipInitialTerminalWindowEnvKey] else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private var shouldSkipInitialTerminalWindow: Bool {
        Self.shouldSkipInitialTerminalWindow(environment: ProcessInfo.processInfo.environment)
    }

    /// The ghostty global state. Only one per process.
    let ghostty: Ghostty.App

    /// The global undo manager for app-level state such as window restoration.
    lazy var undoManager = ExpiringUndoManager()

    /// The current state of the quick terminal.
    private var quickTerminalControllerState: QuickTerminalState = .uninitialized

    /// Our quick terminal. This starts out uninitialized and only initializes if used.
    var quickController: QuickTerminalController {
        switch quickTerminalControllerState {
        case .initialized(let controller):
            return controller

        case .pendingRestore(let state):
            let controller = QuickTerminalController(
                ghostty,
                position: derivedConfig.quickTerminalPosition,
                baseConfig: state.baseConfig,
                restorationState: state
            )
            quickTerminalControllerState = .initialized(controller)
            return controller

        case .uninitialized:
            let controller = QuickTerminalController(
                ghostty,
                position: derivedConfig.quickTerminalPosition,
                restorationState: nil
            )
            quickTerminalControllerState = .initialized(controller)
            return controller
        }
    }

    /// Manages updates
    let updateController = UpdateController()
    var updateViewModel: UpdateViewModel {
        updateController.viewModel
    }

    @MainActor private var _aiTerminalManagerStore: AITerminalManagerStore?
    @MainActor private var _agentRuntimeExecutionCoordinator: AgentRuntimeExecutionCoordinator?
    @MainActor private var markdownDocumentControllers: [UUID: MarkdownDocumentController] = [:]

    @MainActor var aiTerminalManagerStore: AITerminalManagerStore {
        if let store = _aiTerminalManagerStore {
            return store
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { [weak self] in self },
            configurationURL: Self.browserSettingsConfigURL()
        )
        _aiTerminalManagerStore = store
        return store
    }

    @MainActor var existingAITerminalManagerStore: AITerminalManagerStore? {
        _aiTerminalManagerStore
    }

    @MainActor var agentRuntimeExecutionCoordinator: AgentRuntimeExecutionCoordinator {
        if let coordinator = _agentRuntimeExecutionCoordinator {
            return coordinator
        }

        let coordinator = AgentRuntimeExecutionCoordinator(store: aiTerminalManagerStore)
        _agentRuntimeExecutionCoordinator = coordinator
        return coordinator
    }

    @Published private(set) var controlHarnessGatewaySettings = ControlHarnessGatewayAppSettings.load()
    @Published private(set) var controlHarnessGatewayStatusMessage = ""

    @MainActor lazy var controlHarnessAuditLogger = ControlHarnessAuditLogger(
        bundleID: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
    )

    private static func controlHarnessAuthStorageURL(bundleID: String) -> URL {
        let scope = ControlHarnessGatewayAppSettings.StorageScope.current()
        return ControlHarnessAuditLogger
            .baseDirectory(bundleID: bundleID)
            .appendingPathComponent(scope.namespaceKey, isDirectory: true)
            .appendingPathComponent("gateway-auth.json", isDirectory: false)
    }

    lazy var controlHarnessAuth = ControlHarnessAuth(
        storageURL: Self.controlHarnessAuthStorageURL(
            bundleID: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        )
    )

    @MainActor lazy var controlHarnessSampleStore = ControlHarnessSampleStore()

    lazy var controlHarnessPerformanceMonitor = ControlHarnessPerformanceMonitor()

    @MainActor lazy var controlHarnessCore = ControlHarnessCore(
        appDelegate: self,
        auditLogger: controlHarnessAuditLogger,
        sampleStore: controlHarnessSampleStore
    )

    @MainActor
    private func controlHarnessReply(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) async -> ControlHarnessServiceReply {
        let normalizedRequest = request.normalized()
        if normalizedRequest.command == "events.subscribe" || normalizedRequest.command == "terminal.stream.open" {
            return .subscription(controlHarnessCore.handleSubscription(normalizedRequest, socketPath: socketPath))
        }
        return .single(await controlHarnessCore.handleAsync(normalizedRequest, socketPath: socketPath))
    }

    @MainActor
    func applyHostInstanceEnvironment(
        to config: inout Ghostty.SurfaceConfiguration
    ) {
        GhoDexHostInstanceEnvironment.inject(
            into: &config.environmentVariables,
            controlSocketPath: controlHarnessService.socketURL.path,
            processID: ProcessInfo.processInfo.processIdentifier,
            bundleID: Bundle.main.bundleIdentifier,
            executablePath: Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first,
            runtimeDefaultHeartbeatSeconds: aiTerminalManagerStore
                .agentRuntimeSettings
                .sanitized()
                .defaultLeaseDurationSeconds
        )
    }

    @MainActor
    func controlHarnessManagedState(for terminalID: UUID) -> AITerminalManagedState? {
        aiTerminalManagerStore.projectedManagedState(for: terminalID)
    }

    @MainActor
    func controlHarnessGatewayAccessDecision(
        _ request: ControlHarnessRequest
    ) -> ControlHarnessGateway.RequestAuthorization {
        let requestedCommand = request.command
        let request = request.normalized()

        switch request.commandKind {
        case .query, .subscription:
            return .allow
        case .mutation:
            break
        }

        switch request.command {
        case "send-text", "send-key", "run-command", "close-terminal":
            guard let rawTerminalID = request.terminalID,
                  let terminalID = UUID(uuidString: rawTerminalID) else {
                let error = ControlHarnessCoreError.invalidArgument("terminal_id is required")
                return .deny(
                    errorCode: error.code,
                    errorMessage: error.localizedDescription
                )
            }

            let managedState = controlHarnessManagedState(for: terminalID) ?? .manual

            switch managedState {
            case .observed, .managedActive:
                return .allow
            case .managedWaitingApproval:
                return .deny(
                    errorCode: "approval_required",
                    errorMessage: "Remote \(requestedCommand) requires desktop approval for terminal_id=\(rawTerminalID)"
                )
            case .manual:
                return .deny(
                    errorCode: "remote_policy_blocked",
                    errorMessage: "Remote \(requestedCommand) is disabled for terminal state \(managedState.rawValue)"
                )
            case .managedPaused, .managedCompleted, .managedFailed:
                return .deny(
                    errorCode: "remote_policy_blocked",
                    errorMessage: "Remote \(requestedCommand) is disabled for terminal state \(managedState.rawValue)"
                )
            }

        default:
            return .deny(
                errorCode: "remote_policy_blocked",
                errorMessage: "Remote mutation command \(requestedCommand) is disabled over the control-harness gateway"
            )
        }
    }

    lazy var controlHarnessService = ControlHarnessService(
        bundleID: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        requestHandler: { [weak self] request, socketPath in
            guard let self else {
                return .single(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: ControlHarnessCoreError.appUnavailable.code,
                    errorMessage: ControlHarnessCoreError.appUnavailable.localizedDescription
                ))
            }
            return await self.controlHarnessReply(request, socketPath: socketPath)
        }
    )

    @MainActor lazy var controlHarnessReadSampler = ControlHarnessReadSampler(
        bundleID: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        sampleStore: controlHarnessSampleStore,
        performanceMonitor: controlHarnessPerformanceMonitor,
        inventoryProvider: { [weak self] in
            self?.controlHarnessSamplingTargets() ?? []
        }
    )

    lazy var controlHarnessGateway = ControlHarnessGateway(
        bundleID: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        configuration: controlHarnessGatewaySettings.resolvedConfiguration(),
        authManager: controlHarnessAuth,
        requestHandler: { [weak self] request, socketPath in
            guard let self else {
                return .single(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: ControlHarnessCoreError.appUnavailable.code,
                    errorMessage: ControlHarnessCoreError.appUnavailable.localizedDescription
                ))
            }
            return await self.controlHarnessReply(request, socketPath: socketPath)
        },
        requestAuthorizer: { [weak self] request in
            guard let self else {
                return .deny(
                    errorCode: ControlHarnessCoreError.appUnavailable.code,
                    errorMessage: ControlHarnessCoreError.appUnavailable.localizedDescription
                )
            }
            return self.controlHarnessGatewayAccessDecision(request)
        },
        performanceMonitor: controlHarnessPerformanceMonitor
    )

    @MainActor lazy var sshConnectionsController = SSHConnectionsController(
        appDelegate: self,
        store: aiTerminalManagerStore
    )

    @MainActor lazy var newTabPickerController = NewTabPickerController(
        store: aiTerminalManagerStore
    )

    @MainActor lazy var settingsController = SettingsController(appDelegate: self)
    private let browserControlIPCService = BrowserControlIPCService()
    /// The elapsed time since the process was started
    var timeSinceLaunch: TimeInterval {
        return ProcessInfo.processInfo.systemUptime - applicationLaunchTime
    }

    /// Tracks the windows that we hid for toggleVisibility.
    private(set) var hiddenState: ToggleVisibilityState?

    /// The observer for the app appearance.
    private var appearanceObserver: NSKeyValueObservation?

    /// Signals
    private var signals: [DispatchSourceSignal] = []

    /// The custom app icon image that is currently in use.
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appIconSettings = AppIconSettings()
    @Published private(set) var mouseBackForwardSwitchesTabs = false
    @Published private(set) var browserProfilePathOverride: String?
    @Published private(set) var browserRuntimePathOverride: String?

    private var remotePairingQRMenuItem: NSMenuItem?
    private var remotePairingQRCodeWindow: NSWindow?
    private var remotePairingQRCodePayloadJSON: String?
    private var remotePairingQRCodePairingCode: String?
    private var topLevelWindowCloseObserver: NSObjectProtocol?
    private var lastClosedTopLevelWindowKind: LastClosedTopLevelWindowKind?
    private var pendingTerminateReason: String?
    private var pendingTerminateRequestedBy: String?
    private var pendingTerminateSignal: String?
    private var signalTerminationRequested = false

    override init() {
#if DEBUG
        ghostty = Ghostty.App(configPath: ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"])
#else
        ghostty = Ghostty.App()
#endif
        super.init()

        ghostty.delegate = self
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            // Disable the automatic full screen menu item because we handle
            // it manually.
            "NSFullScreenMenuItemEverywhere": false,

            // On macOS 26 RC1, the autofill heuristic controller causes unusable levels
            // of slowdowns and CPU usage in the terminal window under certain [unknown]
            // conditions. We don't know exactly why/how. This disables the full heuristic
            // controller.
            //
            // Practically, this means things like SMS autofill don't work, but that is
            // a desirable behavior to NOT have happen for a terminal, so this is a win.
            // Manual autofill via the `Edit => AutoFill` menu item still work as expected.
            "NSAutoFillHeuristicControllerEnabled": false,
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // System settings overrides
        UserDefaults.standard.register(defaults: [
            // Disable this so that repeated key events make it through to our terminal views.
            "ApplePressAndHoldEnabled": false,
        ])

        // Store our start time
        applicationLaunchTime = ProcessInfo.processInfo.systemUptime
        RuntimeDiagnosticsLogger.beginLifecycleSessionIfNeeded()

        // Check if secure input was enabled when we last quit.
        if UserDefaults.standard.bool(forKey: "SecureInput") != SecureInput.shared.enabled {
            toggleSecureInput(self)
        }

        // Initial config loading
        ghosttyConfigDidChange(config: ghostty.config)

        controlHarnessReadSampler.start()
        controlHarnessService.startIfNeeded()
        controlHarnessGateway.startIfNeeded()
        refreshControlHarnessGatewayStatus()

        // Start our update checker.
        updateController.startUpdater()

        // Register our service provider. This must happen after everything is initialized.
        NSApp.servicesProvider = ServiceProvider()

        if !Self.isRunningUnderTests {
            // This registers the Ghostty => Services menu to exist.
            NSApp.servicesMenu = menuServices
        }

        // Setup a local event monitor for app-level keyboard shortcuts. See
        // localEventHandler for more info why.
        _ = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: localEventHandler)

        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quickTerminalDidChangeVisibility),
            name: .quickTerminalDidChangeVisibility,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyBellDidRing(_:)),
            name: .ghosttyBellDidRing,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(terminalWindowHasBell(_:)),
            name: .terminalWindowBellDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyNewWindow(_:)),
            name: Ghostty.Notification.ghosttyNewWindow,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyNewTab(_:)),
            name: Ghostty.Notification.ghosttyNewTab,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyNewPaneTab(_:)),
            name: Ghostty.Notification.ghosttyNewPaneTab,
            object: nil)

        // Configure user notifications
        let actions = [
            UNNotificationAction(
                identifier: Ghostty.userNotificationActionShow,
                title: AppLocalization.localizedText("Show")
            )
        ]

        let center = UNUserNotificationCenter.current()

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Ghostty.userNotificationCategory,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
        center.delegate = self

        // Observe our appearance so we can report the correct value to libghostty.
        self.appearanceObserver = NSApplication.shared.observe(
            \.effectiveAppearance,
             options: [.new, .initial]
        ) { _, change in
            guard let appearance = change.newValue else { return }
            guard let app = self.ghostty.app else { return }
            let scheme: ghostty_color_scheme_e
            if appearance.isDark {
                scheme = GHOSTTY_COLOR_SCHEME_DARK
            } else {
                scheme = GHOSTTY_COLOR_SCHEME_LIGHT
            }

            ghostty_app_set_color_scheme(app, scheme)
        }

        // Setup our menu
        setupMenuLocalization()
        setupMenuImages()
        installRemotePairingQRMenuItemIfNeeded()
        if shouldShowRemotePairingQROnLaunch() {
            DispatchQueue.main.async { [weak self] in
                self?.requestRemotePairingQRCode(source: .launchPreference)
            }
        }

        // Setup signal handlers
        setupSignals()
        observeTopLevelWindowCloseKind()

        switch Ghostty.launchSource {
        case .app:
            // Don't have to do anything.
            break

        case .zig_run, .cli:
            // Part of launch services (clicking an app, using `open`, etc.) activates
            // the application and brings it to the front. When using the CLI we don't
            // get this behavior, so we have to do it manually.

            // This never gets called until we click the dock icon. This forces it
            // activate immediately.
            applicationDidBecomeActive(.init(name: NSApplication.didBecomeActiveNotification))

            // We run in the background, this forces us to the front.
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.unhide(nil)
                NSApp.arrangeInFront(nil)
            }
        }

        browserControlIPCService.start()
        agentRuntimeExecutionCoordinator.start()
    }

    func applicationDidHide(_ notification: Notification) {
        // Keep track of our hidden state to restore properly
        self.hiddenState = .init()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If we're back manually then clear the hidden state because macOS handles it.
        self.hiddenState = nil

        // First launch stuff
        if !applicationHasBecomeActive {
            applicationHasBecomeActive = true

            // Let's launch our first window. We only do this if we have no other windows. It
            // is possible to have other windows in a few scenarios:
            //   - if we're opening a URL since `application(_:openFile:)` is called before this.
            //   - if we're restoring from persisted state
            if shouldSkipInitialTerminalWindow {
                Self.logger.debug(
                    "Skipping initial terminal window because \(Self.skipInitialTerminalWindowEnvKey, privacy: .public)=\(ProcessInfo.processInfo.environment[Self.skipInitialTerminalWindowEnvKey] ?? "", privacy: .public)"
                )
            } else if TerminalController.all.isEmpty && derivedConfig.initialWindow {
                undoManager.disableUndoRegistration()
                _ = TerminalController.newWindow(ghostty)
                undoManager.enableUndoRegistration()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        defer { lastClosedTopLevelWindowKind = nil }
        return LastWindowCloseTerminationPolicy.shouldTerminateAfterLastWindowClosed(
            shouldQuitAfterLastWindowClosed: derivedConfig.shouldQuitAfterLastWindowClosed,
            lastClosedWindowKind: lastClosedTopLevelWindowKind
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let pendingTerminateReason, pendingTerminateRequestedBy == "signal" {
            var details: [String: String] = [:]
            if let pendingTerminateSignal {
                details["signal_name"] = pendingTerminateSignal
            }
            return acceptTerminate(
                reason: pendingTerminateReason,
                requestedBy: "signal",
                details: details
            )
        }

        if let pendingTerminateReason, pendingTerminateRequestedBy == "relaunch" {
            return acceptTerminate(
                reason: pendingTerminateReason,
                requestedBy: "relaunch"
            )
        }

        let windows = NSApplication.shared.windows
        if windows.isEmpty {
            return acceptTerminate(
                reason: "no_windows",
                requestedBy: "system",
                details: ["window_count": "0"]
            )
        }

        // If we've already accepted to install an update, then we don't need to
        // confirm quit. The user is already expecting the update to happen.
        if updateController.isInstalling {
            return acceptTerminate(
                reason: "update_install_quit",
                requestedBy: "updater"
            )
        }

        // This probably isn't fully safe. The isEmpty check above is aspirational, it doesn't
        // quite work with SwiftUI because windows are retained on close. So instead we check
        // if there are any that are visible. I'm guessing this breaks under certain scenarios.
        //
        // NOTE(mitchellh): I don't think we need this check at all anymore. I'm keeping it
        // here because I don't want to remove it in a patch release cycle but we should
        // target removing it soon.
        if (windows.allSatisfy { !$0.isVisible }) {
            return acceptTerminate(
                reason: "no_visible_windows",
                requestedBy: "system",
                details: ["window_count": "\(windows.count)"]
            )
        }

        // If the user is shutting down, restarting, or logging out, we don't confirm quit.
        why: if let event = NSAppleEventManager.shared().currentAppleEvent {
            // If all Ghostty windows are in the background (i.e. you Cmd-Q from the Cmd-Tab
            // view), then this is null. I don't know why (pun intended) but we have to
            // guard against it.
            guard let keyword = AEKeyword("why?") else { break why }

            if let why = event.attributeDescriptor(forKeyword: keyword) {
                switch why.typeCodeValue {
                case kAEShutDown, kAERestart, kAEReallyLogOut:
                    return acceptTerminate(
                        reason: Self.terminationReason(forAppleEventTypeCode: why.typeCodeValue),
                        requestedBy: "system",
                        details: [
                            "apple_event_type_code": "\(why.typeCodeValue)",
                        ]
                    )

                default:
                    break
                }
            }
        }

        // We have some visible window. Show an app-wide modal to confirm quitting.
        // GhoDex contains more than terminal surfaces, so quitting the app should
        // always be an explicit choice when the user still has visible UI open.
        let alert = NSAlert()
        alert.messageText = L10n.App.quitGhostty
        alert.informativeText = ghostty.needsConfirmQuit
            ? L10n.App.allSessionsTerminated
            : L10n.App.allTabsAndSessionsClosed
        alert.addButton(withTitle: L10n.App.closeGhostty)
        alert.addButton(withTitle: L10n.App.cancel)
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return acceptTerminate(
                reason: "user_confirmed_quit",
                requestedBy: "user",
                details: ["window_count": "\(windows.count)"]
            )

        default:
            RuntimeDiagnosticsLogger.recordLifecycleTerminateCancelled(
                reason: "user_cancelled_quit",
                requestedBy: "user",
                details: ["window_count": "\(windows.count)"]
            )
            clearPendingTerminateState()
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let terminateReason = pendingTerminateReason ?? "application_will_terminate"
        let requestedBy = pendingTerminateRequestedBy ?? "unknown"
        var details: [String: String] = [
            "requested_by": requestedBy,
        ]
        if let pendingTerminateSignal {
            details["signal_name"] = pendingTerminateSignal
        }
        RuntimeDiagnosticsLogger.recordLifecycleWillTerminate(reason: terminateReason, details: details)
        RuntimeDiagnosticsLogger.markLifecycleGracefulTerminate(reason: terminateReason, details: details)

        controlHarnessReadSampler.stop()
        controlHarnessService.stop()
        controlHarnessGateway.stop()
        _agentRuntimeExecutionCoordinator?.stop()

        // We have no notifications we want to persist after death,
        // so remove them all now. In the future we may want to be
        // more selective and only remove surface-targeted notifications.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        browserControlIPCService.stop()
        GhoDexCEFShutdownGlobal()
        clearPendingTerminateState()
    }

    @MainActor
    func relaunchApplication() {
        let relaunchPlan = Self.makeRelaunchProcessPlan(
            executableURL: Bundle.main.executableURL,
            bundlePath: Bundle.main.bundlePath,
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment,
            currentDirectoryPath: FileManager.default.currentDirectoryPath
        )
        DispatchQueue.main.async {
            let process = Process()
            process.executableURL = relaunchPlan.executableURL
            process.arguments = relaunchPlan.arguments
            process.environment = relaunchPlan.environment
            process.currentDirectoryURL = relaunchPlan.currentDirectoryURL

            do {
                try process.run()
                self.pendingTerminateReason = "app_relaunch"
                self.pendingTerminateRequestedBy = "relaunch"
                self.pendingTerminateSignal = nil
                self.signalTerminationRequested = false
                NSApp.terminate(nil)
            } catch {
                Self.logger.error("Failed to relaunch GhoDex: \(error.localizedDescription)")
            }
        }
    }

    static func makeRelaunchProcessPlan(
        executableURL: URL?,
        bundlePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectoryPath: String
    ) -> RelaunchProcessPlan {
        if let executableURL {
            let sanitizedArguments = arguments.dropFirst().filter { argument in
                !argument.hasPrefix("-psn_")
            }
            let currentDirectoryURL: URL?
            let trimmedPath = currentDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPath.isEmpty {
                currentDirectoryURL = nil
            } else {
                currentDirectoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            }
            return .init(
                executableURL: executableURL,
                arguments: Array(sanitizedArguments),
                environment: environment,
                currentDirectoryURL: currentDirectoryURL
            )
        }

        return .init(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-n", bundlePath],
            environment: nil,
            currentDirectoryURL: nil
        )
    }

    /// This is called when the application is already open and someone double-clicks the icon
    /// or clicks the dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If we have visible windows then we allow macOS to do its default behavior
        // of focusing one of them.
        guard !flag else { return true }

        // If we have any windows in our terminal manager we don't do anything.
        // This is possible with flag set to false if there a race where the
        // window is still initializing and is not visible but the user clicked
        // the dock icon.
        guard TerminalController.all.isEmpty else { return true }

        // If the application isn't active yet then we don't want to process
        // this because we're not ready. This happens sometimes in Xcode runs
        // but I haven't seen it happen in releases. I'm unsure why.
        guard applicationHasBecomeActive else { return true }

        // No visible windows, open a new one.
        _ = TerminalController.newWindow(ghostty)
        return false
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // Ghostty will validate as well but we can avoid creating an entirely new
        // surface by doing our own validation here. We can also show a useful error
        // this way.

        var isDirectory = ObjCBool(true)
        guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDirectory) else { return false }

        // Set to true if confirmation is required before starting up the
        // new terminal.
        var requiresConfirm: Bool = false

        // Initialize the surface config which will be used to create the tab or window for the opened file.
        var config = Ghostty.SurfaceConfiguration()

        if isDirectory.boolValue {
            // When opening a directory, check the configuration to decide
            // whether to open in a new tab or new window.
            config.workingDirectory = filename
        } else {
            // Unconditionally require confirmation in the file execution case.
            // In the future I have ideas about making this more fine-grained if
            // we can not inherit of unsandboxed state. For now, we need to confirm
            // because there is a sandbox escape possible if a sandboxed application
            // somehow is tricked into `open`-ing a non-sandboxed application.
            requiresConfirm = true

            // When opening a file, we want to execute the file. To do this, we
            // don't override the command directly, because it won't load the
            // profile/rc files for the shell, which is super important on macOS
            // due to things like Homebrew. Instead, we set the command to
            // `<filename>; exit` which is what Terminal and iTerm2 do.
            config.initialInput = "\(Ghostty.Shell.quote(filename)); exit\n"

            // For commands executed directly, we want to ensure we wait after exit
            // because in most cases scripts don't block on exit and we don't want
            // the window to just flash closed once complete.
            config.waitAfterCommand = true

            // Set the parent directory to our working directory so that relative
            // paths in scripts work.
            config.workingDirectory = (filename as NSString).deletingLastPathComponent
        }

        if requiresConfirm {
            // Confirmation required. We use an app-wide NSAlert for now. In the future we
            // may want to show this as a sheet on the focused window (especially if we're
            // opening a tab). I'm not sure.
            let alert = NSAlert()
            alert.messageText = L10n.App.allowExecute(filename)
            alert.addButton(withTitle: L10n.App.allow)
            alert.addButton(withTitle: L10n.App.cancel)
            alert.alertStyle = .warning
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break

            default:
                return false
            }
        }

        switch ghostty.config.macosDockDropBehavior {
        case .new_tab:
            _ = TerminalController.newTab(
                ghostty,
                from: TerminalController.preferredParent?.window,
                withBaseConfig: config
            )
        case .new_window: _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
        }

        return true
    }

    /// This is called for the dock right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return dockMenu
    }

    /// Setup signal handlers
    private func setupSignals() {
        registerSignalSource(signalNumber: SIGUSR2) { [weak self] in
            guard let self else { return }
            Ghostty.logger.info("reloading configuration in response to SIGUSR2")
            self.ghostty.reloadConfig()
        }
        registerTerminateSignal(SIGTERM)
        registerTerminateSignal(SIGINT)
        registerTerminateSignal(SIGHUP)
    }

    private func registerTerminateSignal(_ signalNumber: Int32) {
        registerSignalSource(signalNumber: signalNumber) { [weak self] in
            self?.handleTerminateSignal(signalNumber)
        }
    }

    private func registerSignalSource(
        signalNumber: Int32,
        handler: @escaping () -> Void
    ) {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()
        signals.append(source)
    }

    private func handleTerminateSignal(_ signalNumber: Int32) {
        let signalName = Self.signalName(for: signalNumber)
        let mappedReason = Self.terminationReason(forSignal: signalNumber)
        RuntimeDiagnosticsLogger.recordLifecycleSignalReceived(
            signalNumber: signalNumber,
            signalName: signalName,
            mappedReason: mappedReason
        )

        pendingTerminateReason = mappedReason
        pendingTerminateRequestedBy = "signal"
        pendingTerminateSignal = signalName

        guard !signalTerminationRequested else { return }
        signalTerminationRequested = true
        NSApp.terminate(nil)
    }

    private func acceptTerminate(
        reason: String,
        requestedBy: String,
        details: [String: String] = [:]
    ) -> NSApplication.TerminateReply {
        pendingTerminateReason = reason
        pendingTerminateRequestedBy = requestedBy
        if let signalName = details["signal_name"] {
            pendingTerminateSignal = signalName
        } else if requestedBy != "signal" {
            pendingTerminateSignal = nil
            signalTerminationRequested = false
        }

        RuntimeDiagnosticsLogger.recordLifecycleTerminateRequested(
            reason: reason,
            requestedBy: requestedBy,
            details: details
        )
        return .terminateNow
    }

    private func clearPendingTerminateState() {
        pendingTerminateReason = nil
        pendingTerminateRequestedBy = nil
        pendingTerminateSignal = nil
        signalTerminationRequested = false
    }

    /// Setup localized titles for menu items that are created in xib but need
    /// to track our runtime language selection.
    private func setupMenuLocalization() {
        installTodoWorkspaceMenuItemIfNeeded()
        menuTodoWorkspace?.title = L10n.SSHConnections.todoPanelTitle
        menuSaveWorkspace?.title = L10n.AITerminalManager.saveWorkspaceAction
    }

    private func installRemotePairingQRMenuItemIfNeeded() {
        guard remotePairingQRMenuItem == nil,
              let appMenu = resolveApplicationMenu() else {
            return
        }

        let menuItem = NSMenuItem(
            title: "Show Remote Pairing QR...",
            action: #selector(showRemotePairingQRCode(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.setImageIfDesired(systemSymbolName: "qrcode")

        let insertionIndex: Int
        if let menuSettingsPanel, appMenu.index(of: menuSettingsPanel) >= 0 {
            insertionIndex = appMenu.index(of: menuSettingsPanel) + 1
        } else {
            insertionIndex = min(4, appMenu.items.count)
        }

        appMenu.insertItem(menuItem, at: insertionIndex)
        remotePairingQRMenuItem = menuItem
    }

    private func resolveApplicationMenu() -> NSMenu? {
        if let menu = menuSettingsPanel?.menu ?? menuAbout?.menu {
            return menu
        }

        let bundleMenuTitle = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "GhoDex"
        if let matchedMenu = NSApp.mainMenu?.items.first(where: { $0.title == bundleMenuTitle })?.submenu {
            return matchedMenu
        }

        return NSApp.mainMenu?.item(at: 1)?.submenu
    }

    private func shouldShowRemotePairingQROnLaunch() -> Bool {
        if controlHarnessGatewaySettings.showPairingQrOnLaunch {
            return true
        }

        guard let rawValue = ProcessInfo.processInfo.environment["GHODEX_CONTROL_HARNESS_PAIRING_QR_ON_LAUNCH"] else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    @objc
    func showRemotePairingQRCode(_ sender: Any?) {
        requestRemotePairingQRCode(source: .manual)
    }

    private func requestRemotePairingQRCode(source: RemotePairingQRCodeRequestSource) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.presentRemotePairingQRCode()
            } catch {
                self.presentRemotePairingQRCodeError(
                    error.localizedDescription,
                    source: source
                )
            }
        }
    }

    @MainActor
    private func presentRemotePairingQRCode() async throws {
        guard controlHarnessGateway.configuration.isEnabled else {
            throw RemotePairingQRCodeError.gatewayDisabled
        }

        guard let port = controlHarnessGateway.listenerPort, port > 0 else {
            throw RemotePairingQRCodeError.gatewayListenerUnavailable
        }

        let host = try preferredGatewayPairingHost()
        let publicEndpoint = resolvedGatewayPairingPublicEndpoint()
        let desktopIdentity = await controlHarnessAuth.desktopIdentityResult()
        let pairing = try await controlHarnessAuth.beginPairing(
            client: "android-qr",
            requestedScopes: ["observe", "mutate"]
        )

        let payload = RemotePairingQRCodePayload(
            host: host,
            port: port,
            pairingCode: pairing.pairingCode,
            desktopID: desktopIdentity.desktopID,
            expiresAt: pairing.expiresAt,
            scopes: pairing.scopes,
            preferredTransport: publicEndpoint == nil ? "lan" : "relay",
            publicEndpoint: publicEndpoint
        )
        let payloadJSON = try payload.serialized()
        presentRemotePairingQRCodeWindow(
            payloadJSON: payloadJSON,
            payload: payload
        )
    }

    @MainActor
    private func presentRemotePairingQRCodeWindow(
        payloadJSON: String,
        payload: RemotePairingQRCodePayload
    ) {
        closeRemotePairingQRCodeWindow(nil)
        remotePairingQRCodePayloadJSON = payloadJSON
        remotePairingQRCodePairingCode = payload.pairingCode

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 478),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Pairing QR"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = makeRemotePairingWindowContentView(
            payloadJSON: payloadJSON,
            payload: payload
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemotePairingQRCodeWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        remotePairingQRCodeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func makeRemotePairingWindowContentView(
        payloadJSON: String,
        payload: RemotePairingQRCodePayload
    ) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 478))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Scan this QR code in GhoDex Remote.")
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "It fills host, port, pairing code, and relay metadata when available.")
        subtitleLabel.alignment = .center
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(subtitleLabel)

        let accessoryView = makeRemotePairingAccessoryView(
            payloadJSON: payloadJSON,
            payload: payload
        )
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(accessoryView)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeRemotePairingQRCodeWindow(_:)))
        let copyJSONButton = NSButton(title: "Copy Pairing JSON", target: self, action: #selector(copyRemotePairingQRCodePayloadJSON(_:)))
        let copyCodeButton = NSButton(title: "Copy Pairing Code", target: self, action: #selector(copyRemotePairingQRCodePairingCode(_:)))
        [closeButton, copyJSONButton, copyCodeButton].forEach { button in
            button.bezelStyle = .rounded
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            buttonStack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttonStack)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            accessoryView.widthAnchor.constraint(equalToConstant: 340),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return container
    }

    private func observeTopLevelWindowCloseKind() {
        guard topLevelWindowCloseObserver == nil else { return }

        topLevelWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let window = notification.object as? NSWindow else { return }

            // Ignore sheets/child windows so top-level tab close classification
            // isn't overwritten by auxiliary window close notifications.
            if window.sheetParent != nil || window.parent != nil {
                return
            }

            if let kind = LastClosedTopLevelWindowKind.resolve(window: window) {
                self.lastClosedTopLevelWindowKind = kind
            }
        }
    }

    @MainActor
    @objc
    private func closeRemotePairingQRCodeWindow(_ sender: Any?) {
        if let window = remotePairingQRCodeWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        remotePairingQRCodeWindow?.close()
        remotePairingQRCodeWindow = nil
        remotePairingQRCodePayloadJSON = nil
        remotePairingQRCodePairingCode = nil
    }

    @MainActor
    @objc
    private func handleRemotePairingQRCodeWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: window
        )
        if remotePairingQRCodeWindow === window {
            remotePairingQRCodeWindow = nil
            remotePairingQRCodePayloadJSON = nil
            remotePairingQRCodePairingCode = nil
        }
    }

    @MainActor
    @objc
    private func copyRemotePairingQRCodePayloadJSON(_ sender: Any?) {
        guard let payloadJSON = remotePairingQRCodePayloadJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payloadJSON, forType: .string)
    }

    @MainActor
    @objc
    private func copyRemotePairingQRCodePairingCode(_ sender: Any?) {
        guard let pairingCode = remotePairingQRCodePairingCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
    }

    @MainActor
    private func makeRemotePairingAccessoryView(
        payloadJSON: String,
        payload: RemotePairingQRCodePayload
    ) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 410))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = makeRemotePairingQRCodeImage(from: payloadJSON)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 260).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(imageView)

        let summary = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        summary.isEditable = false
        summary.isSelectable = true
        summary.drawsBackground = false
        var summaryText = """
        host: \(payload.host):\(payload.port)
        pairing_code: \(payload.pairingCode)
        expires_at: \(payload.expiresAt)
        preferred_transport: \(payload.preferredTransport)
        """
        if let desktopID = payload.desktopID, desktopID.isEmpty == false {
            summaryText += "\ndesktop_id: \(desktopID)"
        }
        if let publicEndpoint = payload.publicEndpoint, publicEndpoint.isEmpty == false {
            summaryText += "\npublic_endpoint: \(publicEndpoint)"
        }
        summary.string = summaryText

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = summary
        stack.addArrangedSubview(scrollView)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    @MainActor
    private func makeRemotePairingQRCodeImage(from payloadJSON: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payloadJSON.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)) else {
            return nil
        }

        let representation = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    private func preferredGatewayPairingHost() throws -> String {
        let listenHost = controlHarnessGateway.configuration.listenHost
        switch listenHost {
        case "127.0.0.1", "localhost", "::1":
            throw RemotePairingQRCodeError.loopbackOnlyListener
        case "0.0.0.0", "::", "":
            if let override = preferredGatewayPairingHostOverride() {
                return override
            }
            guard let address = firstNonLoopbackIPv4Address() else {
                throw RemotePairingQRCodeError.noAdvertisableAddress
            }
            return address
        default:
            if let override = preferredGatewayPairingHostOverride() {
                return override
            }
            return listenHost
        }
    }

    private func preferredGatewayPairingHostOverride() -> String? {
        if let override = ProcessInfo.processInfo.environment["GHODEX_CONTROL_HARNESS_PAIRING_QR_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           override.isEmpty == false {
            return override
        }

        guard let host = controlHarnessGatewaySettings.normalizedPairingAdvertiseHost else {
            return nil
        }
        switch host {
        case "127.0.0.1", "localhost", "::1":
            return nil
        default:
            return host
        }
    }

    private func resolvedGatewayPairingPublicEndpoint() -> String? {
        guard let endpoint = controlHarnessGateway.configuration.publicEndpoint?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              endpoint.isEmpty == false,
              endpoint.hasPrefix("wss://"),
              let parsed = URL(string: endpoint),
              parsed.scheme?.lowercased() == "wss" else {
            return nil
        }
        return endpoint
    }

    private func firstNonLoopbackIPv4Address() -> String? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            return nil
        }
        defer { freeifaddrs(addressList) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            guard let socketAddress = current.pointee.ifa_addr else {
                continue
            }

            let family = socketAddress.pointee.sa_family
            if family != UInt8(AF_INET) {
                continue
            }

            let flags = Int32(current.pointee.ifa_flags)
            if (flags & IFF_LOOPBACK) != 0 {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let address = String(cString: hostBuffer)
                if address.isEmpty == false {
                    return address
                }
            }
        }

        return nil
    }

    @MainActor
    private func presentRemotePairingQRCodeError(
        _ message: String,
        source: RemotePairingQRCodeRequestSource
    ) {
        switch RemotePairingQRCodePresentationPolicy.errorPresentation(for: source) {
        case .blockingModal:
            let alert = NSAlert()
            alert.messageText = "Remote Pairing QR Unavailable"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .logOnly:
            AppDelegate.logger.error(
                "Remote Pairing QR launch request failed without blocking startup: \(message, privacy: .public)"
            )
        }
    }

    private struct RemotePairingQRCodePayload: Encodable {
        let version = 1
        let kind = "ghodex.gateway.pairing"
        let transport = "tcp"
        let host: String
        let port: UInt16
        let pairingCode: String
        let desktopID: String?
        let expiresAt: String
        let scopes: [String]
        let preferredTransport: String
        let publicEndpoint: String?

        enum CodingKeys: String, CodingKey {
            case version
            case kind
            case transport
            case host
            case port
            case pairingCode = "pairing_code"
            case desktopID = "desktop_id"
            case expiresAt = "expires_at"
            case scopes
            case preferredTransport = "preferred_transport"
            case publicEndpoint = "public_endpoint"
        }

        func serialized() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            guard let serialized = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            return serialized
        }
    }

    private enum RemotePairingQRCodeError: LocalizedError {
        case gatewayDisabled
        case gatewayListenerUnavailable
        case loopbackOnlyListener
        case noAdvertisableAddress

        var errorDescription: String? {
            switch self {
            case .gatewayDisabled:
                return "The control gateway is disabled. Enable it in Settings > Gateway first."
            case .gatewayListenerUnavailable:
                return "The control gateway listener port is not available yet."
            case .loopbackOnlyListener:
                return "The control gateway is bound to loopback only. Change the listen host or pairing QR host in Settings > Gateway, or set GHODEX_CONTROL_HARNESS_PAIRING_QR_HOST, before generating a pairing QR."
            case .noAdvertisableAddress:
                return "No non-loopback IPv4 address was found for the pairing QR."
            }
        }
    }

    @MainActor
    func saveControlHarnessGatewaySettings(_ settings: ControlHarnessGatewayAppSettings) {
        let sanitized = settings.sanitized()
        sanitized.save()
        controlHarnessGatewaySettings = sanitized
        controlHarnessGateway.applyConfiguration(sanitized.resolvedConfiguration())
        refreshControlHarnessGatewayStatus()
    }

    @MainActor
    func refreshControlHarnessGatewayStatus() {
        if !controlHarnessGateway.configuration.isEnabled {
            controlHarnessGatewayStatusMessage = L10n.Settings.gatewayStatusDisabled
            return
        }

        if let port = controlHarnessGateway.listenerPort, port > 0 {
            controlHarnessGatewayStatusMessage = L10n.Settings.gatewayStatusListening(
                controlHarnessGateway.configuration.listenHost,
                Int(port)
            )
            return
        }

        if let error = controlHarnessGateway.lastStartupError, error.isEmpty == false {
            controlHarnessGatewayStatusMessage = L10n.Settings.gatewayStatusFailed(error)
            return
        }

        controlHarnessGatewayStatusMessage = L10n.Settings.gatewayStatusPending
    }
    /// Setup all the images for our menu items.
    private func setupMenuImages() {
        // Note: This COULD Be done all in the xib file, but I find it easier to
        // modify this stuff as code.
        self.menuAbout?.setImageIfDesired(systemSymbolName: "info.circle")
        self.menuCheckForUpdates?.setImageIfDesired(systemSymbolName: "square.and.arrow.down")
        self.menuOpenConfig?.setImageIfDesired(systemSymbolName: "gear")
        self.menuSettingsPanel?.setImageIfDesired(systemSymbolName: "slider.horizontal.3")
        self.menuTodoWorkspace?.setImageIfDesired(systemSymbolName: "checklist")
        self.menuReloadConfig?.setImageIfDesired(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90")
        self.menuSecureInput?.setImageIfDesired(systemSymbolName: "lock.display")
        self.menuNewWindow?.setImageIfDesired(systemSymbolName: "macwindow.badge.plus")
        self.menuNewTab?.setImageIfDesired(systemSymbolName: "macwindow")
        self.menuSaveWorkspace?.setImageIfDesired(systemSymbolName: "square.and.arrow.down")
        self.menuSplitRight?.setImageIfDesired(systemSymbolName: "rectangle.righthalf.inset.filled")
        self.menuSplitLeft?.setImageIfDesired(systemSymbolName: "rectangle.leadinghalf.inset.filled")
        self.menuSplitUp?.setImageIfDesired(systemSymbolName: "rectangle.tophalf.inset.filled")
        self.menuSplitDown?.setImageIfDesired(systemSymbolName: "rectangle.bottomhalf.inset.filled")
        self.menuClose?.setImageIfDesired(systemSymbolName: "xmark")
        self.menuPasteSelection?.setImageIfDesired(systemSymbolName: "doc.on.clipboard.fill")
        self.menuIncreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.larger")
        self.menuResetFontSize?.setImageIfDesired(systemSymbolName: "textformat.size")
        self.menuDecreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.smaller")
        self.menuCommandPalette?.setImageIfDesired(systemSymbolName: "filemenu.and.selection")
        self.menuQuickTerminal?.setImageIfDesired(systemSymbolName: "apple.terminal")
        self.menuChangeTabTitle?.setImageIfDesired(systemSymbolName: "pencil.line")
        self.menuTerminalInspector?.setImageIfDesired(systemSymbolName: "scope")
        self.menuReadonly?.setImageIfDesired(systemSymbolName: "eye.fill")
        self.menuSetAsDefaultTerminal?.setImageIfDesired(systemSymbolName: "star.fill")
        self.menuToggleFullScreen?.setImageIfDesired(systemSymbolName: "square.arrowtriangle.4.outward")
        self.menuToggleVisibility?.setImageIfDesired(systemSymbolName: "eye")
        self.menuZoomSplit?.setImageIfDesired(systemSymbolName: "arrow.up.left.and.arrow.down.right")
        self.menuPreviousSplit?.setImageIfDesired(systemSymbolName: "chevron.backward.2")
        self.menuNextSplit?.setImageIfDesired(systemSymbolName: "chevron.forward.2")
        self.menuEqualizeSplits?.setImageIfDesired(systemSymbolName: "inset.filled.topleft.topright.bottomleft.bottomright.rectangle")
        self.menuSelectSplitLeft?.setImageIfDesired(systemSymbolName: "arrow.left")
        self.menuSelectSplitRight?.setImageIfDesired(systemSymbolName: "arrow.right")
        self.menuSelectSplitAbove?.setImageIfDesired(systemSymbolName: "arrow.up")
        self.menuSelectSplitBelow?.setImageIfDesired(systemSymbolName: "arrow.down")
        self.menuMoveSplitDividerUp?.setImageIfDesired(systemSymbolName: "arrow.up.to.line")
        self.menuMoveSplitDividerDown?.setImageIfDesired(systemSymbolName: "arrow.down.to.line")
        self.menuMoveSplitDividerLeft?.setImageIfDesired(systemSymbolName: "arrow.left.to.line")
        self.menuMoveSplitDividerRight?.setImageIfDesired(systemSymbolName: "arrow.right.to.line")
        self.menuFloatOnTop?.setImageIfDesired(systemSymbolName: "square.filled.on.square")
        self.menuFindParent?.setImageIfDesired(systemSymbolName: "text.page.badge.magnifyingglass")
    }

    /// Sync all of our menu item keyboard shortcuts with the Ghostty configuration.
    private func syncMenuShortcuts(_ config: Ghostty.Config) {
        guard ghostty.readiness == .ready else { return }

        syncMenuShortcut(config, action: "check_for_updates", menuItem: self.menuCheckForUpdates)
        syncMenuShortcut(config, action: "open_config", menuItem: self.menuOpenConfig)
        syncMenuShortcut(config, action: "reload_config", menuItem: self.menuReloadConfig)
        syncMenuShortcut(config, action: "quit", menuItem: self.menuQuit)

        syncMenuShortcut(config, action: "new_window", menuItem: self.menuNewWindow)
        // Non-terminal surfaces such as the Settings Panel still need Cmd+T to
        // reach the shared new-tab picker even when no Ghostty surface is focused.
        syncMenuShortcut(config, action: "new_tab", menuItem: self.menuNewTab)
        syncMenuShortcut(config, action: "close_surface", menuItem: self.menuClose)
        syncMenuShortcut(config, action: "close_tab", menuItem: self.menuCloseTab)
        syncMenuShortcut(config, action: "close_window", menuItem: self.menuCloseWindow)
        syncMenuShortcut(config, action: "close_all_windows", menuItem: self.menuCloseAllWindows)
        syncMenuShortcut(config, action: "new_split:right", menuItem: self.menuSplitRight)
        syncMenuShortcut(config, action: "new_split:left", menuItem: self.menuSplitLeft)
        syncMenuShortcut(config, action: "new_split:down", menuItem: self.menuSplitDown)
        syncMenuShortcut(config, action: "new_split:up", menuItem: self.menuSplitUp)

        syncMenuShortcut(config, action: "undo", menuItem: self.menuUndo)
        syncMenuShortcut(config, action: "redo", menuItem: self.menuRedo)
        syncMenuShortcut(config, action: "copy_to_clipboard", menuItem: self.menuCopy)
        syncMenuShortcut(config, action: "paste_from_clipboard", menuItem: self.menuPaste)
        syncMenuShortcut(config, action: "paste_from_selection", menuItem: self.menuPasteSelection)
        syncMenuShortcut(config, action: "select_all", menuItem: self.menuSelectAll)
        syncMenuShortcut(config, action: "start_search", menuItem: self.menuFind)
        syncMenuShortcut(config, action: "search_selection", menuItem: self.menuSelectionForFind)
        syncMenuShortcut(config, action: "scroll_to_selection", menuItem: self.menuScrollToSelection)
        syncMenuShortcut(config, action: "search:next", menuItem: self.menuFindNext)
        syncMenuShortcut(config, action: "search:previous", menuItem: self.menuFindPrevious)

        syncMenuShortcut(config, action: "toggle_split_zoom", menuItem: self.menuZoomSplit)
        syncMenuShortcut(config, action: "goto_split:previous", menuItem: self.menuPreviousSplit)
        syncMenuShortcut(config, action: "goto_split:next", menuItem: self.menuNextSplit)
        syncMenuShortcut(config, action: "goto_split:up", menuItem: self.menuSelectSplitAbove)
        syncMenuShortcut(config, action: "goto_split:down", menuItem: self.menuSelectSplitBelow)
        syncMenuShortcut(config, action: "goto_split:left", menuItem: self.menuSelectSplitLeft)
        syncMenuShortcut(config, action: "goto_split:right", menuItem: self.menuSelectSplitRight)
        syncMenuShortcut(config, action: "resize_split:up,10", menuItem: self.menuMoveSplitDividerUp)
        syncMenuShortcut(config, action: "resize_split:down,10", menuItem: self.menuMoveSplitDividerDown)
        syncMenuShortcut(config, action: "resize_split:right,10", menuItem: self.menuMoveSplitDividerRight)
        syncMenuShortcut(config, action: "resize_split:left,10", menuItem: self.menuMoveSplitDividerLeft)
        syncMenuShortcut(config, action: "equalize_splits", menuItem: self.menuEqualizeSplits)
        syncMenuShortcut(config, action: "reset_window_size", menuItem: self.menuReturnToDefaultSize)

        syncMenuShortcut(config, action: "increase_font_size:1", menuItem: self.menuIncreaseFontSize)
        syncMenuShortcut(config, action: "decrease_font_size:1", menuItem: self.menuDecreaseFontSize)
        syncMenuShortcut(config, action: "reset_font_size", menuItem: self.menuResetFontSize)
        syncMenuShortcut(config, action: "prompt_surface_title", menuItem: self.menuChangeTitle)
        syncMenuShortcut(config, action: "prompt_tab_title", menuItem: self.menuChangeTabTitle)
        syncMenuShortcut(config, action: "toggle_quick_terminal", menuItem: self.menuQuickTerminal)
        syncMenuShortcut(config, action: "toggle_visibility", menuItem: self.menuToggleVisibility)
        syncMenuShortcut(config, action: "toggle_window_float_on_top", menuItem: self.menuFloatOnTop)
        syncMenuShortcut(config, action: "inspector:toggle", menuItem: self.menuTerminalInspector)
        syncMenuShortcut(config, action: "toggle_command_palette", menuItem: self.menuCommandPalette)

        syncMenuShortcut(config, action: "toggle_secure_input", menuItem: self.menuSecureInput)

        // This menu item is NOT synced with the configuration because it disables macOS
        // global fullscreen keyboard shortcut. The shortcut in the Ghostty config will continue
        // to work but it won't be reflected in the menu item.
        //
        // syncMenuShortcut(config, action: "toggle_fullscreen", menuItem: self.menuToggleFullScreen)

        // Dock menu
        reloadDockMenu()
        AppLocalization.localize(menu: NSApp.mainMenu)
    }

    /// Syncs a single menu shortcut for the given action. The action string is the same
    /// action string used for the Ghostty configuration.
    static func applyMenuShortcut(_ config: Ghostty.Config, action: String, to menuItem: NSMenuItem) {
        guard let shortcut = config.keyboardShortcut(for: action) else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            return
        }

        menuItem.keyEquivalent = shortcut.key.character.description
        menuItem.keyEquivalentModifierMask = .init(swiftUIFlags: shortcut.modifiers)
    }

    private func syncMenuShortcut(_ config: Ghostty.Config, action: String, menuItem: NSMenuItem?) {
        guard let menu = menuItem else { return }
        Self.applyMenuShortcut(config, action: action, to: menu)
    }

    private func clearMenuShortcut(_ menuItem: NSMenuItem?) {
        guard let menuItem else { return }
        menuItem.keyEquivalent = ""
        menuItem.keyEquivalentModifierMask = []
    }

    private func installTodoWorkspaceMenuItemIfNeeded() {
        guard menuTodoWorkspace == nil,
              let settingsItem = menuSettingsPanel,
              let menu = settingsItem.menu else { return }

        let item = NSMenuItem(
            title: L10n.SSHConnections.todoPanelTitle,
            action: #selector(showTodoWorkspace(_:)),
            keyEquivalent: "m"
        )
        item.target = self
        item.keyEquivalentModifierMask = [.command, .shift]

        let insertionIndex = menu.index(of: settingsItem) + 1
        menu.insertItem(item, at: max(insertionIndex, 0))
        menuTodoWorkspace = item
    }

    // MARK: Notifications and Events

    /// This handles events from the NSEvent.addLocalEventMonitor. We use this so we can get
    /// events without any terminal windows open.
    private func localEventHandler(_ event: NSEvent) -> NSEvent? {
        return switch event.type {
        case .keyDown:
            localEventKeyDown(event)

        default:
            event
        }
    }

    @MainActor
    func handleMouseBackForwardTabSwitch(_ event: NSEvent, in hostWindow: NSWindow? = nil) -> Bool {
        guard mouseBackForwardSwitchesTabs else { return false }
        guard
            let preferredWindow = hostWindow ?? event.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        else { return false }

        let window = selectedTopLevelWindow(for: preferredWindow)
        guard let window, window.isKeyWindow else { return false }
        guard let tabGroup = window.tabGroup else { return false }

        let tabbedWindows = tabGroup.windows
        guard tabbedWindows.count > 1 else { return false }

        let selectedWindow = tabGroup.selectedWindow ?? window
        guard let selectedIndex = tabbedWindows.firstIndex(where: { $0 == selectedWindow }) else { return false }
        guard let targetIndex = Self.mouseBackForwardTabSwitchTargetIndex(
            forButtonNumber: event.buttonNumber,
            selectedIndex: selectedIndex,
            tabCount: tabbedWindows.count
        ) else {
            return false
        }

        guard targetIndex != selectedIndex else { return false }
        tabbedWindows[targetIndex].makeKeyAndOrderFront(nil)
        return true
    }

    private func localEventKeyDown(_ event: NSEvent) -> NSEvent? {
        // If the tab overview is visible and escape is pressed, close it.
        // This can't POSSIBLY be right and is probably a FirstResponder problem
        // that we should handle elsewhere in our program. But this works and it
        // is guarded by the tab overview currently showing.
        if event.keyCode == 0x35, // Escape key
           let window = NSApp.keyWindow,
           let tabGroup = window.tabGroup,
           tabGroup.isOverviewVisible {
            window.toggleTabOverview(nil)
            return nil
        }

        // If we have a main window then we don't process any of the keys
        // because we let it capture and propagate.
        guard NSApp.mainWindow == nil else { return event }

        // If this event as-is would result in a key binding then we send it.
        if let app = ghostty.app {
            var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
            let match = (event.characters ?? "").withCString { ptr in
                ghosttyEvent.text = ptr
                if !ghostty_app_key_is_binding(app, ghosttyEvent) {
                    return false
                }

                return ghostty_app_key(app, ghosttyEvent)
            }

            // If the key was handled by Ghostty we stop the event chain. If
            // the key wasn't handled then we let it fall through and continue
            // processing. This is important because some bindings may have no
            // affect at this scope.
            if match {
                return nil
            }
        }

        // If this event would be handled by our menu then we do nothing.
        if let mainMenu = NSApp.mainMenu,
           mainMenu.performKeyEquivalent(with: event) {
            return nil
        }

        // If we reach this point then we try to process the key event
        // through the Ghostty key mechanism.

        // Ghostty must be loaded
        guard let ghostty = self.ghostty.app else { return event }

        // Build our event input and call ghostty
        if ghostty_app_key(ghostty, event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)) {
            // The key was used so we want to stop it from going to our Mac app
            Ghostty.logger.debug("local key event handled event=\(event)")
            return nil
        }

        return event
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        syncFloatOnTopMenu(notification.object as? NSWindow)
    }

    @objc private func quickTerminalDidChangeVisibility(_ notification: Notification) {
        guard let quickController = notification.object as? QuickTerminalController else { return }
        self.menuQuickTerminal?.state = if quickController.visible { .on } else { .off }
    }

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // We only care if the configuration is a global configuration, not a surface one.
        guard notification.object == nil else { return }

        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? Ghostty.Config else { return }

        ghosttyConfigDidChange(config: config)
    }

    @objc private func ghosttyBellDidRing(_ notification: Notification) {
        if ghostty.config.bellFeatures.contains(.system) {
            NSSound.beep()
        }

        if ghostty.config.bellFeatures.contains(.audio) {
            if let configPath = ghostty.config.bellAudioPath,
               let sound = NSSound(contentsOfFile: configPath.path, byReference: false) {
                sound.volume = ghostty.config.bellAudioVolume
                sound.play()
            }
        }

        if ghostty.config.bellFeatures.contains(.attention) {
            // Bounce the dock icon if we're not focused.
            NSApp.requestUserAttention(.informationalRequest)
        }

        guard ghostty.config.desktopNotifications else { return }
        guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
        guard !surfaceView.focused else { return }

        notifyForBell(on: surfaceView)
    }

    @objc private func terminalWindowHasBell(_ notification: Notification) {
        guard notification.object is BaseTerminalController else { return }
        syncDockBadge()
    }

    private func syncDockBadge() {
        guard !Self.isRunningUnderTests else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                // If we're authorized and allow badges, then set the badge.
                if settings.badgeSetting == .enabled {
                    DispatchQueue.main.async {
                        self.setDockBadge()
                    }
                }

            case .notDetermined:
                // Not determined yet, request authorization for badge
                center.requestAuthorization(options: [.badge]) { granted, error in
                    if let error = error {
                        Self.logger.warning("Error requesting badge authorization: \(error)")
                        return
                    }

                    if granted {
                        // Permission granted, set the badge
                        DispatchQueue.main.async {
                            self.setDockBadge()
                        }
                    }
                }

            case .denied, .provisional, .ephemeral:
                // In these known non-authorized states, do not attempt to set the badge.
                break

            @unknown default:
                // Handle future unknown states by doing nothing.
                break
            }
        }
    }

    private func notifyForBell(on surfaceView: Ghostty.SurfaceView) {
        guard !Self.isRunningUnderTests else { return }
        let center = UNUserNotificationCenter.current()
        let showNotification = {
            DispatchQueue.main.async {
                surfaceView.showUserNotification(
                    title: AppLocalization.localizedString("terminal.notification.bell.title"),
                    body: AppLocalization.localizedString("terminal.notification.bell.body"),
                    requireFocus: false
                )
            }
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                showNotification()

            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        Self.logger.warning("Error requesting bell notification authorization: \(error)")
                        return
                    }

                    guard granted else { return }
                    showNotification()
                }

            case .denied, .provisional, .ephemeral:
                break

            @unknown default:
                break
            }
        }
    }

    @objc private func ghosttyNewWindow(_ notification: Notification) {
        let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? Ghostty.SurfaceConfiguration
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }

    @MainActor @objc private func ghosttyNewTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
        guard let window = surfaceView.window else { return }

        // Keep keyboard-triggered new-tab actions aligned with the picker flow
        // used by the menu and tab-bar affordances in the sidebar workspace UI.
        guard window.windowController is TerminalController else { return }
        showNewTabPicker(from: selectedTopLevelWindow(for: window) ?? window)
    }

    @MainActor @objc private func ghosttyNewPaneTab(_ notification: Notification) {
        let notificationSurface = notification.object as? Ghostty.SurfaceView
        let notificationWindow = selectedTopLevelWindow(for: notificationSurface?.window)
        let notificationController = selectedTerminalController(for: notificationWindow)

        guard let controller = activeTerminalController(preferred: notificationWindow)
            ?? notificationController else { return }

        let window = selectedTopLevelWindow(for: controller.window) ?? notificationWindow
        guard let sourceSurface = activePaneSurface(in: controller) else { return }

        showNewPaneTabPicker(from: window, in: controller, sourceSurface: sourceSurface)
    }

    private func setDockBadge() {
        let bellCount = NSApp.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .reduce(0) { $0 + ($1.bell ? 1 : 0) }
        let wantsBadge = ghostty.config.bellFeatures.contains(.attention) && bellCount > 0
        let label = wantsBadge ? (bellCount > 99 ? "99+" : String(bellCount)) : nil
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    private func ghosttyConfigDidChange(config: Ghostty.Config) {
        // Update the config we need to store
        self.derivedConfig = DerivedConfig(config)
        appIconSettings = AppIconSettings(config: config)
        mouseBackForwardSwitchesTabs = config.ghodexMouseBackForwardSwitchesTabs
        syncBrowserProfileConfig(config)
        syncBrowserRuntimeConfig(config)
        syncBrowserRemoteDebugPortConfig(config)
        // Browser tabs now initialize CEF lazily when the first page model is
        // constructed. Doing eager global init here can stall launch before the
        // Browser IPC service starts, which makes isolated control-plane
        // validation impossible even though the runtime is otherwise present.

        // Depending on the "window-save-state" setting we have to set the NSQuitAlwaysKeepsWindows
        // configuration. This is the only way to carefully control whether macOS invokes the
        // state restoration system.
        switch config.windowSaveState {
        case "never": UserDefaults.standard.setValue(false, forKey: "NSQuitAlwaysKeepsWindows")
        case "always": UserDefaults.standard.setValue(true, forKey: "NSQuitAlwaysKeepsWindows")
        case "default": fallthrough
        default: UserDefaults.standard.removeObject(forKey: "NSQuitAlwaysKeepsWindows")
        }

        // Sync our auto-update settings. If SUEnableAutomaticChecks (in our Info.plist) is
        // explicitly false (NO), auto-updates are disabled. Otherwise, we use the behavior
        // defined by our "auto-update" configuration (if set) or fall back to Sparkle
        // user-based defaults.
        if Bundle.main.infoDictionary?["SUEnableAutomaticChecks"] as? Bool == false {
            updateController.updater.automaticallyChecksForUpdates = false
            updateController.updater.automaticallyDownloadsUpdates = false
        } else if let autoUpdate = config.autoUpdate {
            updateController.updater.automaticallyChecksForUpdates =
                autoUpdate == .check || autoUpdate == .download
            updateController.updater.automaticallyDownloadsUpdates =
                autoUpdate == .download
            /*
             To test `auto-update` easily, uncomment the line below and
             delete `SUEnableAutomaticChecks` in GhoDex-Info.plist.

             Note: When `auto-update = download`, you may need to
             `Clean Build Folder` if a background install has already begun.
             */
            // updateController.updater.checkForUpdatesInBackground()
        }

        // Config could change keybindings, so update everything that depends on that.
        // XCTest launches the full app without a stable interactive main-menu tree, which
        // otherwise produces AppKit menu-consistency noise during targeted test runs.
        if !Self.isRunningUnderTests {
            syncMenuShortcuts(config)
        }
        TerminalController.all.forEach { $0.relabelTabs() }

        // Update our badge since config can change what we show.
        syncDockBadge()

        // Config could change window appearance. We wrap this in an async queue because when
        // this is called as part of application launch it can deadlock with an internal
        // AppKit mutex on the appearance.
        DispatchQueue.main.async { self.syncAppearance(config: config) }

        // Decide whether to hide/unhide app from dock and app switcher
        switch config.macosHidden {
        case .never:
            NSApp.setActivationPolicy(.regular)

        case .always:
            NSApp.setActivationPolicy(.accessory)
        }

        // If we have configuration errors, we need to show them.
        let c = ConfigurationErrorsController.sharedInstance
        c.errors = config.errors
        if c.errors.count > 0 {
            if c.window == nil || !c.window!.isVisible {
                c.showWindow(self)
            }
        }

        // We need to handle our global event tap depending on if there are global
        // events that we care about in Ghostty.
        if ghostty_app_has_global_keybinds(ghostty.app!) {
            if timeSinceLaunch > 5 {
                // If the process has been running for awhile we enable right away
                // because no windows are likely to pop up.
                GlobalEventTap.shared.enable()
            } else {
                // If the process just started, we wait a couple seconds to allow
                // the initial windows and so on to load so our permissions dialog
                // doesn't get buried.
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    GlobalEventTap.shared.enable()
                }
            }
        } else {
            GlobalEventTap.shared.disable()
        }

        updateAppIcon(from: config)
    }

    /// Sync the appearance of our app with the theme specified in the config.
    private func syncAppearance(config: Ghostty.Config) {
        NSApplication.shared.appearance = .init(ghosttyConfig: config)
    }

    private func updateAppIcon(from config: Ghostty.Config) {
        let resolvedSettings = AppIconSettings(config: config)
        let resolvedIcon = AppIcon(config: config)
        let resolvedImage = resolvedSettings.previewImage(in: .main)
        DispatchQueue.main.async {
            self.appIconSettings = resolvedSettings
            self.appIcon = resolvedImage
            self.applyLiveAppIcon(resolvedImage, resolvedIcon: resolvedIcon)
        }
        DispatchQueue.global().async {
            let defaultsTargets = [
                UserDefaults.standard,
                Bundle.main.bundleIdentifier.flatMap(UserDefaults.init(suiteName:)),
            ].compactMap { $0 }

            for defaults in defaultsTargets {
                defaults.removeObject(forKey: "CustomGhosttyIcon")
                defaults.appIcon = resolvedIcon
            }
            DistributedNotificationCenter.default()
                .postNotificationName(.ghosttyIconDidChange, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    @MainActor
    private func applyLiveAppIcon(_ image: NSImage?, resolvedIcon: AppIcon?) {
        let defaultImage = AppIcon.officialImage(in: .main, appBundleURL: Bundle.main.bundleURL)
        NSApp.applicationIconImage = image ?? defaultImage ?? NSApp.applicationIconImage
        applyLiveDockTileIcon(image)
        syncBundleIcon(image, resolvedIcon: resolvedIcon)
    }

    @MainActor
    private func applyLiveDockTileIcon(_ image: NSImage?) {
        let dockTile = NSApp.dockTile
        guard let image else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }

        let iconView = NSImageView(frame: CGRect(origin: .zero, size: dockTile.size))
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = image
        dockTile.contentView = iconView
        dockTile.display()
    }

    @MainActor
    private func syncBundleIcon(_ image: NSImage?, resolvedIcon: AppIcon?) {
        guard
            let appBundleURL = Bundle.main.bundleURL as URL?,
            AppBundleIconMutationPolicy.shouldWriteBundleIcon(at: appBundleURL)
        else {
            return
        }

        let appBundlePath = appBundleURL.path
        if resolvedIcon == nil {
            NSWorkspace.shared.setIcon(nil, forFile: appBundlePath)
        } else {
            NSWorkspace.shared.setIcon(image, forFile: appBundlePath)
        }
        NSWorkspace.shared.noteFileSystemChanged(appBundlePath)
    }

    var managedBrowserProfilePath: String {
        BrowserPaths.defaultManagedProfileRoot().path
    }

    var managedBrowserRuntimePath: String {
        BrowserPaths.defaultManagedCEFRuntimeRoot().path
    }

    @MainActor
    func chooseBrowserProfilePath(currentPath: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Settings.browserBrowseButton
        panel.message = L10n.Settings.browserPickerMessage

        if let currentPath = Self.normalizedBrowserProfilePath(currentPath) {
            panel.directoryURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        } else {
            panel.directoryURL = BrowserPaths.defaultManagedProfileRoot().deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    @MainActor
    func chooseBrowserRuntimePath(currentPath: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Settings.browserBrowseButton
        panel.message = L10n.Settings.browserRuntimePickerMessage

        if let currentPath = Self.normalizedBrowserRuntimePath(currentPath) {
            panel.directoryURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        } else {
            panel.directoryURL = BrowserPaths.defaultManagedCEFRuntimeRoot().deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    @MainActor
    func saveBrowserProfilePathSetting(_ rawValue: String) throws {
        let normalized = Self.normalizedBrowserProfilePath(rawValue)
        if let normalized {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw NSError(
                    domain: "GhoDexBrowserSettings",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.Settings.browserInvalidPath]
                )
            }
        }

        let configURL = Self.browserSettingsConfigURL()
        try Self.saveBrowserSettingsConfig(profilePath: normalized, runtimePath: browserRuntimePathOverride, to: configURL)

        applyBrowserProfileDefaults(path: normalized)
        browserProfilePathOverride = normalized
        ghostty.reloadConfig()
    }

    @MainActor
    func saveVisualAppIconSettings(_ rawSettings: AppIconSettings) throws {
        let settings = rawSettings.sanitized
        let configURL = Self.browserSettingsConfigURL()
        try Self.saveAppIconSettingsConfig(settings, to: configURL)
        ghostty.reloadConfig()
    }

    @MainActor
    func saveMouseBackForwardTabSwitchingSetting(_ enabled: Bool) throws {
        let configURL = Self.browserSettingsConfigURL()
        try Self.saveMouseNavigationSettingsConfig(enabled: enabled, to: configURL)
        ghostty.reloadConfig()
    }

    @MainActor
    func saveBrowserSettings(profilePath rawProfileValue: String, runtimePath rawRuntimeValue: String) throws {
        let normalizedProfile = Self.normalizedBrowserProfilePath(rawProfileValue)
        if let normalizedProfile {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: normalizedProfile, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw NSError(
                    domain: "GhoDexBrowserSettings",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.Settings.browserInvalidPath]
                )
            }
        }

        let normalizedRuntime = Self.normalizedBrowserRuntimePath(rawRuntimeValue)
        if let normalizedRuntime {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: normalizedRuntime, isDirectory: true),
                    withIntermediateDirectories: true
                )
            } catch {
                throw NSError(
                    domain: "GhoDexBrowserSettings",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.Settings.browserInvalidRuntimePath]
                )
            }
        }

        let configURL = Self.browserSettingsConfigURL()
        try Self.saveBrowserSettingsConfig(profilePath: normalizedProfile, runtimePath: normalizedRuntime, to: configURL)

        applyBrowserProfileDefaults(path: normalizedProfile)
        applyBrowserRuntimeDefaults(path: normalizedRuntime)
        browserProfilePathOverride = normalizedProfile
        browserRuntimePathOverride = normalizedRuntime
        ghostty.reloadConfig()
    }

    private func syncBrowserProfileConfig(_ config: Ghostty.Config) {
        let fileOverrides = Self.loadBrowserSettingsConfig()
        let resolved = Self.resolvedBrowserProfilePath(
            fileOverride: fileOverrides.profilePath,
            configOverride: config.ghodexBrowserProfilePath
        )
        browserProfilePathOverride = resolved
        applyBrowserProfileDefaults(path: resolved)
        if BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() {
            UserDefaults.standard.synchronize()
        }
    }

    private func syncBrowserRuntimeConfig(_ config: Ghostty.Config) {
        let fileOverrides = Self.loadBrowserSettingsConfig()
        let resolved = Self.resolvedBrowserRuntimePath(
            fileOverride: fileOverrides.runtimePath,
            configOverride: config.ghodexBrowserRuntimePath
        )
        browserRuntimePathOverride = resolved
        applyBrowserRuntimeDefaults(path: resolved)
        if BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() {
            UserDefaults.standard.synchronize()
        }
    }

    private func syncBrowserRemoteDebugPortConfig(_ config: Ghostty.Config) {
        let resolved = Self.normalizedBrowserRemoteDebugPort(config.ghodexBrowserRemoteDebugPort)
        applyBrowserRemoteDebugPortDefaults(port: resolved)
        if BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() {
            UserDefaults.standard.synchronize()
        }
    }

    private func initializeBrowserCEFIfPossible() {
        guard !GhoDexCEFIsInitialized(), GhoDexCEFBuildHasRuntime() else { return }
        _ = GhoDexCEFInitializeGlobal()
    }

    private func applyBrowserProfileDefaults(path: String?) {
        guard BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() else { return }
        if let path {
            UserDefaults.standard.set(path, forKey: BrowserPaths.profileDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BrowserPaths.profileDefaultsKey)
        }
    }

    private func applyBrowserRuntimeDefaults(path: String?) {
        guard BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() else { return }
        if let path {
            UserDefaults.standard.set(path, forKey: BrowserPaths.runtimeDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BrowserPaths.runtimeDefaultsKey)
        }
    }

    private func applyBrowserRemoteDebugPortDefaults(port: Int?) {
        guard BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() else { return }
        if let port {
            UserDefaults.standard.set(port, forKey: BrowserPaths.remoteDebugPortDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
        }
    }

    // MARK: - Restorable State

    /// We support NSSecureCoding for restorable state. Required as of macOS Sonoma (14) but a good idea anyways.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func application(_ app: NSApplication, willEncodeRestorableState coder: NSCoder) {
        Self.logger.debug("application will save window state")

        guard ghostty.config.windowSaveState != "never" else { return }

        // Encode our quick terminal state if we have it.
        switch quickTerminalControllerState {
        case .initialized(let controller) where controller.restorable:
            let data = QuickTerminalRestorableState(from: controller)
            data.encode(with: coder)

        case .pendingRestore(let state):
            state.encode(with: coder)

        default:
            break
        }
    }

    func application(_ app: NSApplication, didDecodeRestorableState coder: NSCoder) {
        Self.logger.debug("application will restore window state")

        // Decode our quick terminal state.
        if ghostty.config.windowSaveState != "never",
            let state = QuickTerminalRestorableState(coder: coder) {
            quickTerminalControllerState = .pendingRestore(state)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive: UNNotificationResponse,
        withCompletionHandler: () -> Void
    ) {
        ghostty.handleUserNotification(response: didReceive)
        withCompletionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent: UNNotification,
        withCompletionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
        let shouldPresent = ghostty.shouldPresentNotification(notification: willPresent)
        let options: UNNotificationPresentationOptions = shouldPresent ? [.banner, .sound] : []
        withCompletionHandler(options)
    }

    // MARK: - GhosttyAppDelegate

    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        for c in TerminalController.all {
            for view in c.allSurfaces where view.id == uuid {
                return view
            }
        }

        return nil
    }

    @MainActor
    func controlHarnessReadableSurface(for terminalID: UUID) -> (any ControlHarnessReadableSurface)? {
        findSurface(forUUID: terminalID)
    }

    @MainActor
    func controlHarnessSamplingTargets() -> [ControlHarnessSamplerTarget] {
        return TerminalController.all.flatMap { controller in
            controller.allSurfaces.map { surface in
                let isFocused = controller.focusedSurface?.id == surface.id
                let isVisible = controller.visibleSurfaces.contains(where: { $0.id == surface.id })
                let managedState = aiTerminalManagerStore.projectedManagedState(for: surface.id)
                return ControlHarnessSamplerTarget(
                    terminalID: surface.id.uuidString,
                    surface: surface,
                    activityClass: .init(
                        managedState: managedState,
                        isFocused: isFocused,
                        isVisible: isVisible
                    )
                )
            }
        }
    }

    @MainActor
    func controlHarnessSamplingActivityClass(for terminalID: UUID) -> ControlHarnessSamplingActivityClass? {
        controlHarnessSamplingTargets()
            .first(where: { $0.terminalID == terminalID.uuidString })?
            .activityClass
    }

    @MainActor
    func openMarkdownDocument(at fileURL: URL, tabbedInto parentWindow: NSWindow?) {
        guard let target = MarkdownDocumentTarget(fileURL: fileURL) else {
            NSWorkspace.shared.open(fileURL)
            return
        }

        let controllerID = UUID()
        let controller = MarkdownDocumentController(
            appDelegate: self,
            target: target
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.markdownDocumentControllers.removeValue(forKey: controllerID)
            }
        }

        markdownDocumentControllers[controllerID] = controller
        controller.show(tabbedInto: parentWindow)
    }

    @MainActor
    func controlHarnessSendText(_ text: String, to terminalID: UUID) -> Bool {
        guard let surface = findSurface(forUUID: terminalID) else {
            return false
        }

        surface.aiManagerSendText(text)
        return true
    }

    @MainActor
    func controlHarnessSendKey(_ key: String, to terminalID: UUID) -> Bool {
        guard let surface = findSurface(forUUID: terminalID) else {
            return false
        }

        return surface.aiManagerSendControlKey(key)
    }

    @MainActor
    func controlHarnessRunCommand(_ command: String, to terminalID: UUID) -> Bool {
        guard let surface = findSurface(forUUID: terminalID) else {
            return false
        }

        surface.aiManagerRunCommand(command)
        return true
    }

    @MainActor
    func controlHarnessAwaitTextEcho(_ text: String, to terminalID: UUID, timeout: TimeInterval = 0.35) -> Bool {
        guard let surface = findSurface(forUUID: terminalID) else {
            return false
        }

        let expected = Self.normalizedControlHarnessEchoText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected.isEmpty == false else {
            return true
        }

        let deadline = Date().addingTimeInterval(max(0.01, timeout))
        repeat {
            let snapshot = surface.controlHarnessScreenText(refresh: true).content
            let normalizedSnapshot = Self.normalizedControlHarnessEchoText(snapshot)
            if normalizedSnapshot.contains(expected) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline

        return false
    }

    @MainActor
    func controlHarnessCloseTerminal(_ terminalID: UUID) -> Bool {
        guard let surface = findSurface(forUUID: terminalID),
              let controller = surface.window?.windowController as? BaseTerminalController else {
            return false
        }

        // Harness callers are non-interactive, so this path must never block on
        // the normal confirm-close sheet for a live process.
        controller.closeSurface(surface, withConfirmation: false)
        return true
    }

    private static func normalizedControlHarnessEchoText(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let withoutANSI = controlHarnessANSIEscapeRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: ""
        )
        return withoutANSI.replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - Dock Menu

    private func reloadDockMenu() {
        let newWindow = NSMenuItem(
            title: AppLocalization.localizedText("New Window"),
            action: #selector(newWindow),
            keyEquivalent: ""
        )
        let newTab = NSMenuItem(
            title: AppLocalization.localizedText("New Tab"),
            action: #selector(newTab),
            keyEquivalent: ""
        )

        dockMenu.removeAllItems()
        dockMenu.addItem(newWindow)
        dockMenu.addItem(newTab)
    }

    // MARK: - Global State

    func setSecureInput(_ mode: Ghostty.SetSecureInput) {
        let input = SecureInput.shared
        switch mode {
        case .on:
            input.global = true

        case .off:
            input.global = false

        case .toggle:
            input.global.toggle()
        }
        self.menuSecureInput?.state = if input.global { .on } else { .off }
        UserDefaults.standard.set(input.global, forKey: "SecureInput")
    }

    // MARK: - IB Actions

    @IBAction func openConfig(_ sender: Any?) {
        Ghostty.App.openConfig()
    }

    @IBAction func reloadConfig(_ sender: Any?) {
        ghostty.reloadConfig()
    }

    @IBAction func checkForUpdates(_ sender: Any?) {
        updateController.checkForUpdates()
        // UpdateSimulator.happyPath.simulate(with: updateViewModel)
    }

    @IBAction func newWindow(_ sender: Any?) {
        _ = TerminalController.newWindow(ghostty)
    }

    @IBAction func newTab(_ sender: Any?) {
        showNewTabPicker(from: TerminalController.preferredParent?.window ?? NSApp.keyWindow)
    }

    @IBAction func newBrowserTab(_ sender: Any?) {
        let parentWindow = selectedTopLevelWindow(for: NSApp.keyWindow)
            ?? selectedTopLevelWindow(for: TerminalController.preferredParent?.window)
        _ = BrowserTabController.newTab(ghostty, from: parentWindow)
    }

    @IBAction func newPaneTab(_ sender: Any?) {
        activeTerminalController()?.newPaneTab(sender)
    }

    @IBAction func closeTab(_ sender: Any?) {
        let actionTopLevelWindow = preferredTopLevelWindow(for: sender)

        if let terminalController = actionTopLevelWindow?.windowController as? TerminalController {
            terminalController.closeTab(sender)
            return
        }

        if let tabController = activeTopLevelTabController(preferred: actionTopLevelWindow) {
            tabController.closeTabImmediately(registerRedo: true)
            return
        }

        (actionTopLevelWindow ?? NSApp.keyWindow)?.performClose(sender)
    }

    @IBAction func splitRight(_ sender: Any?) {
        handleSplitActionFallback(
            sender,
            browserSplitAxis: .vertical,
            terminalSplitDirection: .right
        ) { controller, resolvedSender in
            controller.splitRight(resolvedSender)
        }
    }

    @IBAction func splitLeft(_ sender: Any?) {
        handleSplitActionFallback(
            sender,
            browserSplitAxis: .vertical,
            terminalSplitDirection: .left
        ) { controller, resolvedSender in
            controller.splitLeft(resolvedSender)
        }
    }

    @IBAction func splitDown(_ sender: Any?) {
        handleSplitActionFallback(
            sender,
            browserSplitAxis: .horizontal,
            terminalSplitDirection: .down
        ) { controller, resolvedSender in
            controller.splitDown(resolvedSender)
        }
    }

    @IBAction func splitUp(_ sender: Any?) {
        handleSplitActionFallback(
            sender,
            browserSplitAxis: .horizontal,
            terminalSplitDirection: .up
        ) { controller, resolvedSender in
            controller.splitUp(resolvedSender)
        }
    }

    @IBAction func saveWorkspace(_ sender: Any?) {
        guard let controller = saveWorkspaceController(for: sender) else { return }
        presentSaveWorkspacePrompt(for: controller)
    }

    @MainActor
    private func saveWorkspaceController(for sender: Any?) -> TerminalController? {
        if let controller = sender as? TerminalController {
            return controller
        }

        if let window = sender as? NSWindow {
            return window.windowController as? TerminalController
        }

        if let menuItem = sender as? NSMenuItem {
            if let controller = menuItem.representedObject as? TerminalController {
                return controller
            }

            if let window = menuItem.representedObject as? NSWindow {
                return window.windowController as? TerminalController
            }
        }

        return activeTerminalController()
    }

    @MainActor
    private func presentSaveWorkspacePrompt(for controller: TerminalController) {
        let alert = NSAlert()
        alert.messageText = L10n.AITerminalManager.saveWorkspaceAction
        alert.informativeText = L10n.AITerminalManager.saveWorkspacePrompt
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = controller.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? controller.titleOverride ?? ""
            : (controller.window?.title ?? "")
        alert.accessoryView = textField
        alert.addButton(withTitle: L10n.AITerminalManager.saveWorkspace)
        alert.addButton(withTitle: L10n.Common.cancel)
        alert.window.initialFirstResponder = textField

        guard let window = controller.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.saveWorkspace(controller, name: textField.stringValue, in: window)
        }
    }

    @MainActor
    private func saveWorkspace(
        _ controller: TerminalController,
        name: String,
        in window: NSWindow
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = aiTerminalManagerStore.existingSavedWorkspaceTemplate(named: trimmedName) {
            presentReplaceWorkspacePrompt(
                for: controller,
                name: trimmedName,
                existingTemplate: existing,
                in: window
            )
            return
        }

        aiTerminalManagerStore.saveCurrentWorkspace(from: controller, name: trimmedName)
        presentSaveWorkspaceErrorIfNeeded(in: window)
    }

    @MainActor
    private func presentReplaceWorkspacePrompt(
        for controller: TerminalController,
        name: String,
        existingTemplate: AITerminalSavedWorkspaceTemplate,
        in window: NSWindow
    ) {
        let alert = NSAlert()
        alert.messageText = L10n.AITerminalManager.replaceWorkspaceTitle
        alert.informativeText = L10n.AITerminalManager.replaceWorkspaceMessage(name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.AITerminalManager.replaceWorkspace)
        alert.addButton(withTitle: L10n.Common.cancel)

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.aiTerminalManagerStore.saveCurrentWorkspace(
                from: controller,
                name: name,
                replacingID: existingTemplate.id
            )
            self.presentSaveWorkspaceErrorIfNeeded(in: window)
        }
    }

    @MainActor
    private func presentSaveWorkspaceErrorIfNeeded(in window: NSWindow) {
        guard let message = aiTerminalManagerStore.lastError else { return }

        let errorAlert = NSAlert()
        errorAlert.messageText = L10n.AITerminalManager.couldNotSaveWorkspace
        errorAlert.informativeText = message
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: L10n.App.ok)
        errorAlert.beginSheetModal(for: window)
    }

    @IBAction func changeTitleContext(_ sender: Any?) {
        activeTopLevelTabController(preferred: NSApp.keyWindow)?.promptTabTitle()
    }

    @IBAction func previousPaneTab(_ sender: Any?) {
        activeTerminalController()?.previousPaneTab(sender)
    }

    @IBAction func nextPaneTab(_ sender: Any?) {
        activeTerminalController()?.nextPaneTab(sender)
    }

    @MainActor
    func showNewTabPicker(from window: NSWindow?) {
        let browserAction = { [weak self] in
            guard let self else { return }
            let parentWindow = self.selectedTopLevelWindow(for: window)
                ?? self.selectedTopLevelWindow(for: NSApp.keyWindow)
            _ = BrowserTabController.newTab(self.ghostty, from: parentWindow)
        }
        let workspaceMapAction = { [weak self] in
            guard let self else { return }
            let parentWindow = self.selectedTopLevelWindow(for: window)
                ?? self.selectedTopLevelWindow(for: NSApp.keyWindow)
            _ = WorkspaceMapController.newTab(self.ghostty, from: parentWindow)
        }

        if let window {
            newTabPickerController.show(
                relativeTo: window,
                mode: .topLevel,
                includeBrowserEntry: true,
                onOpenBrowser: browserAction,
                onOpenWorkspaceMap: workspaceMapAction
            )
            return
        }

        newTabPickerController.show(
            relativeTo: nil,
            mode: .topLevel,
            includeBrowserEntry: true,
            onOpenBrowser: browserAction,
            onOpenWorkspaceMap: workspaceMapAction
        )
    }

    @MainActor
    func showNewPaneTabPicker(
        from window: NSWindow?,
        in controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView
    ) {
        let openHost = { [weak self, weak controller, weak sourceSurface] (host: AITerminalHost) in
            guard let self, let controller, let sourceSurface else { return }
            self.aiTerminalManagerStore.openInPaneTab(host: host, controller: controller, sourceSurface: sourceSurface)
        }

        if let window {
            newTabPickerController.show(
                relativeTo: window,
                mode: .paneChild,
                title: AppLocalization.localizedText("New Pane Tab"),
                subtitle: L10n.SSHConnections.newTabPickerSubtitle,
                includeBrowserEntry: false,
                onOpenHost: openHost)
            return
        }

        aiTerminalManagerStore.openInPaneTab(host: .local, controller: controller, sourceSurface: sourceSurface)
    }

    @MainActor
    private func handleSplitActionFallback(
        _ sender: Any?,
        browserSplitAxis: BrowserDeckSplitAxis,
        terminalSplitDirection: SplitTree<TerminalPane>.NewDirection,
        terminalAction: @escaping (TerminalController, Any) -> Void
    ) {
        guard let context = splitActionContext(for: sender) else { return }

        switch context {
        case .terminal(let terminalController):
            guard let sourceSurface = activePaneSurface(in: terminalController) else {
                terminalAction(terminalController, self)
                return
            }

            let defaultSplit: () -> Void = { [weak self, weak terminalController, weak sourceSurface] in
                guard let self, let terminalController else { return }
                let splitSource = self.activePaneSurface(in: terminalController) ?? sourceSurface
                guard let splitSource else {
                    terminalAction(terminalController, self)
                    return
                }
                _ = terminalController.newSplit(
                    at: splitSource,
                    direction: terminalSplitDirection
                )
            }

            showSplitPicker(
                relativeTo: terminalController.window,
                title: AppLocalization.localizedText("Split Pane"),
                subtitle: AppLocalization.localizedText("Choose a target for the new split pane."),
                includeBrowserEntry: false,
                onCancel: defaultSplit,
                onOpenHost: { [weak self, weak terminalController, weak sourceSurface] host in
                    guard let self, let terminalController else { return }
                    let splitSource = self.activePaneSurface(in: terminalController) ?? sourceSurface
                    guard let splitSource else { return }
                    self.aiTerminalManagerStore.openInSplit(
                        host: host,
                        controller: terminalController,
                        sourceSurface: splitSource,
                        direction: terminalSplitDirection
                    )
                },
                onOpenBrowser: nil
            )

        case .browser(let browserController):
            _ = browserSplitAxis
            browserController.model.collapseSplitDeck()
        }
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    private func showSplitPicker(
        relativeTo window: NSWindow?,
        title: String,
        subtitle: String,
        includeBrowserEntry: Bool,
        onCancel: (() -> Void)?,
        onOpenHost: ((AITerminalHost) -> Void)?,
        onOpenBrowser: (() -> Void)?
    ) {
        newTabPickerController.show(
            relativeTo: window,
            mode: .paneChild,
            title: title,
            subtitle: subtitle,
            includeBrowserEntry: includeBrowserEntry,
            onCancel: onCancel,
            onOpenHost: onOpenHost,
            onOpenBrowser: onOpenBrowser
        )
    }

    private func activeTerminalController(preferred window: NSWindow? = nil) -> TerminalController? {
        if let controller = selectedTerminalController(for: window) {
            return controller
        }

        if let controller = selectedTerminalController(for: NSApp.keyWindow) {
            return controller
        }

        if let controller = selectedTerminalController(for: NSApp.mainWindow) {
            return controller
        }

        if let controller = selectedTerminalController(for: TerminalController.preferredParent?.window) {
            return controller
        }

        return TerminalController.preferredParent
    }

    private func activeTopLevelTabController(preferred window: NSWindow? = nil) -> TopLevelTabController? {
        if let controller = selectedTopLevelTabController(for: window) {
            return controller
        }

        if let controller = selectedTopLevelTabController(for: NSApp.keyWindow) {
            return controller
        }

        if let controller = selectedTopLevelTabController(for: NSApp.mainWindow) {
            return controller
        }

        return selectedTopLevelTabController(for: TerminalController.preferredParent?.window)
    }

    private func selectedTerminalController(for window: NSWindow?) -> TerminalController? {
        selectedTopLevelWindow(for: window)?.windowController as? TerminalController
    }

    private func selectedTopLevelTabController(for window: NSWindow?) -> TopLevelTabController? {
        selectedTopLevelWindow(for: window)?.windowController as? TopLevelTabController
    }

    private func selectedTopLevelWindow(for window: NSWindow?) -> NSWindow? {
        window?.tabGroup?.selectedWindow ?? window
    }

    private func topLevelWindow(from sender: Any?) -> NSWindow? {
        if let window = sender as? NSWindow {
            return selectedTopLevelWindow(for: window)
        }

        if let view = sender as? NSView {
            return selectedTopLevelWindow(for: view.window)
        }

        if let windowController = sender as? NSWindowController {
            return selectedTopLevelWindow(for: windowController.window)
        }

        if let menuItem = sender as? NSMenuItem {
            if let window = menuItem.representedObject as? NSWindow {
                return selectedTopLevelWindow(for: window)
            }

            if let windowController = menuItem.representedObject as? NSWindowController {
                return selectedTopLevelWindow(for: windowController.window)
            }
        }

        return nil
    }

    private func preferredTopLevelWindow(for sender: Any?) -> NSWindow? {
        if let senderWindow = topLevelWindow(from: sender) {
            return senderWindow
        }

        if let keyWindow = selectedTopLevelWindow(for: NSApp.keyWindow) {
            return keyWindow
        }

        if let mainWindow = selectedTopLevelWindow(for: NSApp.mainWindow) {
            return mainWindow
        }

        return selectedTopLevelWindow(for: TerminalController.preferredParent?.window)
    }

    private enum SplitActionContext {
        case terminal(TerminalController)
        case browser(BrowserTabController)
    }

    private func splitActionContext(for sender: Any?) -> SplitActionContext? {
        let preferredWindow = preferredTopLevelWindow(for: sender)

        if let terminalController = selectedTerminalController(for: preferredWindow) {
            return .terminal(terminalController)
        }

        if let browserController = selectedTopLevelTabController(for: preferredWindow) as? BrowserTabController {
            return .browser(browserController)
        }

        if let browserController = activeTopLevelTabController(preferred: preferredWindow) as? BrowserTabController {
            return .browser(browserController)
        }

        if let terminalController = activeTerminalController(preferred: preferredWindow) {
            return .terminal(terminalController)
        }

        return nil
    }

    private func activePaneSurface(
        in controller: TerminalController
    ) -> Ghostty.SurfaceView? {
        controller.effectiveFocusedSurface().flatMap { controller.pane(for: $0)?.activeSurface ?? $0 }
    }

    @IBAction func closeAllWindows(_ sender: Any?) {
        let browserControllers = BrowserTabController.all
        let workspaceMapControllers = WorkspaceMapController.all
        let confirmWindow = TerminalController.all
            .first(where: { $0.allSurfaces.contains(where: { $0.needsConfirmQuit }) })?
            .allSurfaces.first(where: { $0.needsConfirmQuit })?
            .window

        guard let confirmWindow else {
            TerminalController.closeAllWindowsImmediately()
            BrowserTabController.closeAllWindowsImmediately()
            WorkspaceMapController.closeAllWindowsImmediately()
            AboutController.shared.hide()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.App.closeAllWindowsQuestion
        alert.informativeText = L10n.App.allSessionsTerminated
        alert.addButton(withTitle: L10n.App.closeAllWindows)
        alert.addButton(withTitle: L10n.App.cancel)
        alert.alertStyle = .warning
        alert.beginSheetModal(for: confirmWindow) { response in
            guard response == .alertFirstButtonReturn else { return }

            // Avoid focus loss while closing a whole tab group under Stage Manager.
            alert.window.orderOut(nil)
            TerminalController.closeAllWindowsImmediately()
            browserControllers.forEach { $0.window?.close() }
            workspaceMapControllers.forEach { $0.window?.close() }
            AboutController.shared.hide()
        }

        AboutController.shared.hide()
    }

    @IBAction func showAbout(_ sender: Any?) {
        AboutController.shared.show()
    }

    @IBAction func showHelp(_ sender: Any) {
        guard let url = URL(string: "https://github.com/LeonSGP43/GhoDex#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func toggleSecureInput(_ sender: Any) {
        setSecureInput(.toggle)
    }

    @IBAction func toggleQuickTerminal(_ sender: Any) {
        quickController.toggle()
    }

    /// Toggles visibility of all Ghosty Terminal windows. When hidden, activates Ghostty as the frontmost application
    @IBAction func toggleVisibility(_ sender: Any) {
        // If we have focus, then we hide all windows.
        if NSApp.isActive {
            // Toggle visibility doesn't do anything if the focused window is native
            // fullscreen. This is only relevant if Ghostty is active.
            guard let keyWindow = NSApp.keyWindow,
                  !keyWindow.styleMask.contains(.fullScreen) else { return }

            NSApp.hide(nil)
            return
        }

        // If we're not active, we want to become active
        NSApp.activate(ignoringOtherApps: true)

        // Bring all windows to the front. Note: we don't use NSApp.unhide because
        // that will unhide ALL hidden windows. We want to only bring forward the
        // ones that we hid.
        hiddenState?.restore()
        hiddenState = nil
    }

    @IBAction func bringAllToFront(_ sender: Any) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        NSApplication.shared.arrangeInFront(sender)
    }

    @IBAction func undo(_ sender: Any?) {
        undoManager.undo()
    }

    @IBAction func redo(_ sender: Any?) {
        undoManager.redo()
    }

    private struct DerivedConfig {
        let initialWindow: Bool
        let shouldQuitAfterLastWindowClosed: Bool
        let quickTerminalPosition: QuickTerminalPosition

        init() {
            self.initialWindow = true
            self.shouldQuitAfterLastWindowClosed = false
            self.quickTerminalPosition = .top
        }

        init(_ config: Ghostty.Config) {
            self.initialWindow = config.initialWindow
            self.shouldQuitAfterLastWindowClosed = config.shouldQuitAfterLastWindowClosed
            self.quickTerminalPosition = config.quickTerminalPosition
        }
    }

    struct ToggleVisibilityState {
        let hiddenWindows: [Weak<NSWindow>]
        let keyWindow: Weak<NSWindow>?

        fileprivate init() {
            // We need to know the key window so that we can bring focus back to the
            // right window if it was hidden.
            self.keyWindow = if let keyWindow = NSApp.keyWindow {
                .init(keyWindow)
            } else {
                nil
            }

            // We need to keep track of the windows that were visible because we only
            // want to bring back these windows if we remove the toggle.
            //
            // We also ignore fullscreen windows because they don't hide anyways.
            var visibleWindows = [Weak<NSWindow>]()
            NSApp.windows.filter {
                $0.isVisible &&
                !$0.styleMask.contains(.fullScreen)
            }.forEach { window in
                // We only keep track of selectedWindow if it's in a tabGroup,
                // so we can keep its selection state when restoring
                let windowToHide = window.tabGroup?.selectedWindow ?? window
                if !visibleWindows.contains(where: { $0.value === windowToHide }) {
                    visibleWindows.append(Weak(windowToHide))
                }
            }
            self.hiddenWindows = visibleWindows
        }

        func restore() {
            hiddenWindows.forEach { $0.value?.orderFrontRegardless() }
            keyWindow?.value?.makeKey()
        }
    }
}

// MARK: Floating Windows

extension AppDelegate {
    func syncFloatOnTopMenu(_ window: NSWindow?) {
        guard let window = (window ?? NSApp.keyWindow) as? TerminalWindow else {
            // If some other window became key we always turn this off
            self.menuFloatOnTop?.state = .off
            return
        }

        self.menuFloatOnTop?.state = window.level == .floating ? .on : .off
    }

    @IBAction func floatOnTop(_ menuItem: NSMenuItem) {
        menuItem.state = menuItem.state == .on ? .off : .on
        guard let window = NSApp.keyWindow else { return }
        window.level = menuItem.state == .on ? .floating : .normal
    }

    @IBAction func useAsDefault(_ sender: NSMenuItem) {
        let ud = UserDefaults.standard
        let key = TerminalWindow.defaultLevelKey
        if menuFloatOnTop?.state == .on {
            ud.set(NSWindow.Level.floating, forKey: key)
        } else {
            ud.removeObject(forKey: key)
        }
    }

    @IBAction func setAsDefaultTerminal(_ sender: NSMenuItem) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .unixExecutable) { error in
            guard let error else { return }
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = L10n.App.failedSetDefaultTerminal
                alert.informativeText = L10n.App.setDefaultTerminalFailure(error.localizedDescription)
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setAsDefaultTerminal(_:)):
            return NSWorkspace.shared.defaultTerminal != Bundle.main.bundleURL

        case #selector(floatOnTop(_:)),
            #selector(useAsDefault(_:)):
            // Float on top items only active if the key window is a primary
            // terminal window (not quick terminal).
            return NSApp.keyWindow is TerminalWindow

        case #selector(saveWorkspace(_:)):
            return saveWorkspaceController(for: item) != nil

        case #selector(undo(_:)):
            if undoManager.canUndo {
                item.title = L10n.App.undo(undoManager.undoActionName)
            } else {
                item.title = AppLocalization.localizedText("Undo")
            }
            return undoManager.canUndo

        case #selector(redo(_:)):
            if undoManager.canRedo {
                item.title = L10n.App.redo(undoManager.redoActionName)
            } else {
                item.title = AppLocalization.localizedText("Redo")
            }
            return undoManager.canRedo

        default:
            return true
        }
    }
}

extension AppDelegate {
    private static let browserSettingsStartMarker = "# >>> GhoDex browser settings >>>"
    private static let browserSettingsEndMarker = "# <<< GhoDex browser settings <<<"
    private static let iconSettingsStartMarker = "# >>> GhoDex app icon settings >>>"
    private static let iconSettingsEndMarker = "# <<< GhoDex app icon settings <<<"
    private static let mouseNavigationSettingsStartMarker = "# >>> GhoDex mouse navigation settings >>>"
    private static let mouseNavigationSettingsEndMarker = "# <<< GhoDex mouse navigation settings <<<"
    private static let browserProfileConfigKey = "ghodex-browser-profile-path"
    private static let browserRuntimeConfigKey = "ghodex-browser-runtime-path"
    private static let browserRemoteDebugPortConfigKey = "ghodex-browser-remote-debug-port"
    private static let mouseBackForwardSwitchesTabsConfigKey = "ghodex-mouse-back-forward-switches-tabs"
    private static let macosIconConfigKey = "macos-icon"
    private static let macosCustomIconConfigKey = "macos-custom-icon"
    private static let macosIconFrameConfigKey = "macos-icon-frame"
    private static let macosIconGhostColorConfigKey = "macos-icon-ghost-color"
    private static let macosIconScreenColorConfigKey = "macos-icon-screen-color"

    static func terminationReason(forSignal signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGTERM:
            return "signal_sigterm"
        case SIGINT:
            return "signal_sigint"
        case SIGHUP:
            return "signal_sighup"
        default:
            return "signal_\(signalNumber)"
        }
    }

    static func signalName(for signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGTERM:
            return "SIGTERM"
        case SIGINT:
            return "SIGINT"
        case SIGHUP:
            return "SIGHUP"
        case SIGUSR2:
            return "SIGUSR2"
        default:
            return "SIG\(signalNumber)"
        }
    }

    static func mouseBackForwardTabSwitchTargetIndex(
        forButtonNumber buttonNumber: Int,
        selectedIndex: Int,
        tabCount: Int
    ) -> Int? {
        guard tabCount > 1 else { return nil }
        guard (0..<tabCount).contains(selectedIndex) else { return nil }

        switch buttonNumber {
        case 3:
            return selectedIndex == 0 ? tabCount - 1 : selectedIndex - 1
        case 4:
            return selectedIndex == tabCount - 1 ? 0 : selectedIndex + 1
        default:
            return nil
        }
    }

    static func terminationReason(forAppleEventTypeCode typeCode: DescType) -> String {
        switch typeCode {
        case kAEShutDown:
            return "system_shutdown"
        case kAERestart:
            return "system_restart"
        case kAEReallyLogOut:
            return "system_logout"
        default:
            return "system_apple_event_\(typeCode)"
        }
    }

    fileprivate static func normalizedBrowserProfilePath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).standardizingPath
    }

    fileprivate static func normalizedBrowserRuntimePath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).standardizingPath
    }

    fileprivate static func normalizedBrowserRemoteDebugPort(_ value: Int) -> Int? {
        guard (1...65535).contains(value) else { return nil }
        return value
    }

    fileprivate static func validatedExistingBrowserOverridePath(
        _ normalizedPath: String?,
        settingName: String,
        source: String
    ) -> String? {
        guard let normalizedPath else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            AppDelegate.logger.warning(
                "Ignoring invalid Browser \(settingName, privacy: .public) override from \(source, privacy: .public): \(normalizedPath, privacy: .public)"
            )
            return nil
        }

        return normalizedPath
    }

    fileprivate static func resolvedBrowserProfilePath(
        fileOverride: String?,
        configOverride: String?
    ) -> String? {
        if fileOverride != nil {
            return validatedExistingBrowserOverridePath(
                normalizedBrowserProfilePath(fileOverride),
                settingName: "profile",
                source: "browser settings block"
            )
        }

        return validatedExistingBrowserOverridePath(
            normalizedBrowserProfilePath(configOverride),
            settingName: "profile",
            source: "Ghostty config"
        )
    }

    fileprivate static func resolvedBrowserRuntimePath(
        fileOverride: String?,
        configOverride: String?
    ) -> String? {
        if fileOverride != nil {
            return validatedExistingBrowserOverridePath(
                normalizedBrowserRuntimePath(fileOverride),
                settingName: "runtime",
                source: "browser settings block"
            )
        }

        return validatedExistingBrowserOverridePath(
            normalizedBrowserRuntimePath(configOverride),
            settingName: "runtime",
            source: "Ghostty config"
        )
    }

    fileprivate static func browserSettingsConfigURL() -> URL {
        let fileManager = FileManager.default
        if let envPath = ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"],
           !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath, isDirectory: false)
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return url
        }

        if let path = Ghostty.App.configPath(), !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: false)
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return url
        }

        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        let bundleID = Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.ghodex", isDirectory: false)
    }

    fileprivate static func saveBrowserSettingsConfig(profilePath: String?, runtimePath: String?, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingText: String
        if fileManager.fileExists(atPath: url.path) {
            existingText = try String(contentsOf: url, encoding: .utf8)
        } else {
            existingText = ""
        }

        let stripped = stripBrowserSettingsConfig(from: existingText)
        let block = browserSettingsConfigBlock(profilePath: profilePath, runtimePath: runtimePath)
        let normalized = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalized.isEmpty ? "\(block)\n" : "\(normalized)\n\n\(block)\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    fileprivate static func saveAppIconSettingsConfig(_ settings: AppIconSettings, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingText: String
        if fileManager.fileExists(atPath: url.path) {
            existingText = try String(contentsOf: url, encoding: .utf8)
        } else {
            existingText = ""
        }

        let stripped = stripAppIconSettingsConfig(from: existingText)
        let block = appIconSettingsConfigBlock(settings.sanitized)
        let normalized = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalized.isEmpty ? "\(block)\n" : "\(normalized)\n\n\(block)\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    fileprivate static func saveMouseNavigationSettingsConfig(enabled: Bool, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingText: String
        if fileManager.fileExists(atPath: url.path) {
            existingText = try String(contentsOf: url, encoding: .utf8)
        } else {
            existingText = ""
        }

        let stripped = stripMouseNavigationSettingsConfig(from: existingText)
        let block = mouseNavigationSettingsConfigBlock(enabled: enabled)
        let normalized = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalized.isEmpty ? "\(block)\n" : "\(normalized)\n\n\(block)\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    fileprivate static func loadBrowserSettingsConfig() -> (profilePath: String?, runtimePath: String?) {
        let url = browserSettingsConfigURL()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }

        return (
            profilePath: browserSettingValue(for: browserProfileConfigKey, in: text),
            runtimePath: browserSettingValue(for: browserRuntimeConfigKey, in: text)
        )
    }

    private static func browserSettingsConfigBlock(profilePath: String?, runtimePath: String?) -> String {
        [
            browserSettingsStartMarker,
            "\(browserProfileConfigKey) = \(configStringLiteral(profilePath ?? ""))",
            "\(browserRuntimeConfigKey) = \(configStringLiteral(runtimePath ?? ""))",
            browserSettingsEndMarker,
        ].joined(separator: "\n")
    }

    private static func appIconSettingsConfigBlock(_ settings: AppIconSettings) -> String {
        let normalized = settings.sanitized
        return [
            iconSettingsStartMarker,
            "\(macosIconConfigKey) = \(configStringLiteral(normalized.icon.rawValue))",
            iconSettingsEndMarker,
        ].joined(separator: "\n")
    }

    private static func mouseNavigationSettingsConfigBlock(enabled: Bool) -> String {
        [
            mouseNavigationSettingsStartMarker,
            "\(mouseBackForwardSwitchesTabsConfigKey) = \(enabled ? "true" : "false")",
            mouseNavigationSettingsEndMarker,
        ].joined(separator: "\n")
    }

    private static func stripBrowserSettingsConfig(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var insideManagedBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == browserSettingsStartMarker {
                insideManagedBlock = true
                continue
            }

            if trimmed == browserSettingsEndMarker {
                insideManagedBlock = false
                continue
            }

            if insideManagedBlock {
                continue
            }

            if trimmed.hasPrefix("\(browserProfileConfigKey) =") ||
                trimmed == browserProfileConfigKey ||
                trimmed.hasPrefix("\(browserRuntimeConfigKey) =") ||
                trimmed == browserRuntimeConfigKey {
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private static func stripMouseNavigationSettingsConfig(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var insideManagedBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == mouseNavigationSettingsStartMarker {
                insideManagedBlock = true
                continue
            }

            if trimmed == mouseNavigationSettingsEndMarker {
                insideManagedBlock = false
                continue
            }

            if insideManagedBlock {
                continue
            }

            if trimmed.hasPrefix("\(mouseBackForwardSwitchesTabsConfigKey) =") ||
                trimmed == mouseBackForwardSwitchesTabsConfigKey {
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private static func stripAppIconSettingsConfig(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var insideManagedBlock = false
        let managedKeys = [
            macosIconConfigKey,
            macosCustomIconConfigKey,
            macosIconFrameConfigKey,
            macosIconGhostColorConfigKey,
            macosIconScreenColorConfigKey,
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == iconSettingsStartMarker {
                insideManagedBlock = true
                continue
            }

            if trimmed == iconSettingsEndMarker {
                insideManagedBlock = false
                continue
            }

            if insideManagedBlock {
                continue
            }

            if managedKeys.contains(where: { trimmed.hasPrefix("\($0) =") || trimmed == $0 }) {
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private static func configStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func browserSettingValue(for key: String, in text: String) -> String? {
        var result: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) =") else { continue }

            guard let separatorIndex = trimmed.firstIndex(of: "=") else { continue }
            let rawValue = trimmed[trimmed.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
            let data = Data("[\(rawValue)]".utf8)
            guard
                let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
                let value = decoded.first
            else {
                continue
            }

            result = value
        }

        return result
    }
}

/// Represents the state of the quick terminal controller.
private enum QuickTerminalState {
    /// Controller has not been initialized and has no pending restoration state.
    case uninitialized
    /// Restoration state is pending; controller will use this when first accessed.
    case pendingRestore(QuickTerminalRestorableState)
    /// Controller has been initialized.
    case initialized(QuickTerminalController)
}
