import AppKit
import SwiftUI

@MainActor
final class WelcomeSetupController: NSWindowController, NSWindowDelegate {
    let model: WelcomeSetupModel
    private unowned let appDelegate: AppDelegate

    init(appDelegate: AppDelegate, store: AITerminalManagerStore) {
        self.appDelegate = appDelegate
        self.model = WelcomeSetupModel(appDelegate: appDelegate, store: store)

        let hostingController = NSHostingController(
            rootView: WelcomeSetupView(model: model)
                .environmentObject(appDelegate)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.WelcomeSetup.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 940, height: 780))
        window.minSize = NSSize(width: 860, height: 700)

        super.init(window: window)
        self.window?.delegate = self
        self.model.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        model.syncFromSources()
        window.title = L10n.WelcomeSetup.windowTitle
        window.contentViewController = NSHostingController(
            rootView: WelcomeSetupView(model: model)
                .environmentObject(appDelegate)
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

@MainActor
final class WelcomeSetupModel: ObservableObject {
    enum StatusTone {
        case neutral
        case success
        case warning
        case danger
    }

    enum BrowserRuntimeState {
        case ready
        case unsupportedBuild
        case initializing
        case initializationFailed
        case unavailable
    }

    weak var controller: WelcomeSetupController?

    private unowned let appDelegate: AppDelegate
    private let store: AITerminalManagerStore
    private var browserInstallTask: Task<Void, Never>?

    @Published var selectedLanguage: AppLanguageSetting = .system
    @Published var mouseBackForwardSwitchesTabs = false
    @Published var builtInIconSelection: Ghostty.MacOSIcon = .official

    @Published var learningEnabled = true
    @Published var learningChatWorkspacePath = ""
    @Published var learningNotesRelativePath = ""
    @Published var learningStatusMessage: String?
    @Published var learningStatusTone: StatusTone = .neutral
    @Published var learningOperationInProgress = false

    @Published var todoEnabled = true
    @Published var todoWorkspaceRootPath = ""
    @Published var todoStatusMessage: String?
    @Published var todoStatusTone: StatusTone = .neutral

    @Published var browserUsesManagedProfile = true
    @Published var browserProfilePathText = ""
    @Published var browserUsesManagedRuntime = true
    @Published var browserRuntimePathText = ""
    @Published var browserRuntimeState: BrowserRuntimeState = .unavailable
    @Published var browserInstallPhase: BrowserRuntimeInstallPhase = .idle

    @Published var gatewayEnabled = false
    @Published var gatewayListenHost = ""
    @Published var gatewayPortText = ""
    @Published var gatewayPairingHost = ""
    @Published var gatewayShowQrOnLaunch = false
    @Published var gatewaySemanticProfile: ControlHarnessSemanticProfile = .defaultValue

    @Published var saveFeedbackMessage: String?
    @Published var saveFeedbackTone: StatusTone = .neutral

    init(appDelegate: AppDelegate, store: AITerminalManagerStore) {
        self.appDelegate = appDelegate
        self.store = store
        syncFromSources()
    }

    var needsRestart: Bool {
        selectedLanguage != AppLanguageSetting.launchedSetting
    }

    var previewIconImage: NSImage {
        AppIconSettings(icon: builtInIconSelection).previewImage(in: .main) ?? NSImage()
    }

    var managedBrowserProfilePath: String {
        appDelegate.managedBrowserProfilePath
    }

    var managedBrowserRuntimePath: String {
        appDelegate.managedBrowserRuntimePath
    }

    var resolvedLearnWorkspacePath: String {
        let trimmedChatWorkspacePath = learningChatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatWorkspacePath.isEmpty else {
            return store.learningSettings.defaultProjectPath
        }
        return AITerminalLearningSettings.learnWorkspacePath(fromChatWorkspacePath: trimmedChatWorkspacePath)
    }

    var resolvedNotesAbsolutePath: String {
        let trimmedNotesPath = learningNotesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotesPath = trimmedNotesPath.isEmpty
            ? AITerminalLearningSettings.defaultNotesRelativePath
            : trimmedNotesPath

        if resolvedNotesPath.hasPrefix("/") {
            return resolvedNotesPath
        }

        return URL(fileURLWithPath: resolvedLearnWorkspacePath, isDirectory: true)
            .appendingPathComponent(resolvedNotesPath, isDirectory: false)
            .path
    }

    var browserRuntimeAssessment: BrowserRuntimeMediaAssessment {
        BrowserPaths.runtimeMediaAssessment(
            runtimePath: browserUsesManagedRuntime ? managedBrowserRuntimePath : browserRuntimePathText,
            usesManagedRuntime: browserUsesManagedRuntime
        )
    }

    var browserRuntimeStatusText: String {
        switch browserRuntimeState {
        case .ready:
            return L10n.WelcomeSetup.browserRuntimeReady
        case .unsupportedBuild:
            return L10n.WelcomeSetup.browserRuntimeUnsupported
        case .initializing:
            return L10n.WelcomeSetup.browserRuntimeInitializing
        case .initializationFailed:
            return L10n.WelcomeSetup.browserRuntimeFailed
        case .unavailable:
            return L10n.WelcomeSetup.browserRuntimeUnavailable
        }
    }

    var browserRuntimeStatusTone: StatusTone {
        switch browserRuntimeState {
        case .ready:
            return .success
        case .unsupportedBuild, .initializationFailed:
            return .danger
        case .initializing, .unavailable:
            return .warning
        }
    }

    var browserAssessmentText: String {
        switch browserRuntimeAssessment.reason {
        case .managedChromiumDistribution:
            return L10n.Settings.browserRuntimeMediaManagedWarning
        case .codecEnabledRuntime:
            return L10n.Settings.browserRuntimeMediaCodecEnabledHint
        case .chromiumBrandedRuntime:
            return L10n.Settings.browserRuntimeMediaChromiumWarning(
                browserRuntimeAssessment.runtimeSource
                    ?? browserRuntimeAssessment.runtimePath
                    ?? L10n.Common.untitled
            )
        case .customRuntimeUnverified:
            return L10n.Settings.browserRuntimeMediaCustomHint
        }
    }

    var browserAssessmentTone: StatusTone {
        switch browserRuntimeAssessment.reason {
        case .codecEnabledRuntime:
            return .success
        case .managedChromiumDistribution, .chromiumBrandedRuntime, .customRuntimeUnverified:
            return .warning
        }
    }

    var browserInstallStatusText: String? {
        browserInstallPhase.statusText
    }

    var browserInstallStatusTone: StatusTone {
        switch browserInstallPhase {
        case .idle:
            return .neutral
        case .installed:
            return .success
        case .failed:
            return .danger
        case .downloading, .extracting, .installing:
            return .warning
        }
    }

    var gatewayStatusMessage: String {
        appDelegate.controlHarnessGatewayStatusMessage
    }

    var managedBrowserRuntimeHintLines: [String] {
        BrowserPaths.installHintLines()
    }

    var canInstallManagedRuntime: Bool {
        browserUsesManagedRuntime &&
            browserRuntimeState != .ready &&
            browserRuntimeState != .unsupportedBuild &&
            !browserInstallPhase.isWorking &&
            BrowserPaths.configuredCEFRuntimeOverride() == nil
    }

    var canRetryBrowserActivation: Bool {
        browserRuntimeState != .ready &&
            browserRuntimeState != .unsupportedBuild &&
            !browserInstallPhase.isWorking
    }

    var isBusy: Bool {
        learningOperationInProgress || browserInstallPhase.isWorking
    }

    func syncFromSources() {
        selectedLanguage = AppLanguageSetting.storedSelection()
        mouseBackForwardSwitchesTabs = appDelegate.mouseBackForwardSwitchesTabs
        builtInIconSelection = appDelegate.appIconSettings.sanitized.icon

        let learningSettings = store.learningSettings
        learningEnabled = learningSettings.enabled
        learningChatWorkspacePath = AITerminalLearningSettings.chatWorkspacePath(
            fromLearnWorkspacePath: learningSettings.defaultProjectPath
        )
        learningNotesRelativePath = learningSettings.notesRelativePath

        let todoSettings = store.todoSettings
        todoEnabled = todoSettings.enabled
        todoWorkspaceRootPath = todoSettings.workspaceRootPath

        let currentProfilePath = appDelegate.browserProfilePathOverride ?? ""
        browserUsesManagedProfile = currentProfilePath.isEmpty
        browserProfilePathText = currentProfilePath

        let currentRuntimePath = appDelegate.browserRuntimePathOverride ?? ""
        browserUsesManagedRuntime = currentRuntimePath.isEmpty
        browserRuntimePathText = currentRuntimePath
        refreshBrowserRuntimeState()

        let gatewaySettings = appDelegate.controlHarnessGatewaySettings
        gatewayEnabled = gatewaySettings.isEnabled
        gatewayListenHost = gatewaySettings.listenHost
        gatewayPortText = String(gatewaySettings.listenPort)
        gatewayPairingHost = gatewaySettings.pairingAdvertiseHost
        gatewayShowQrOnLaunch = gatewaySettings.showPairingQrOnLaunch
        gatewaySemanticProfile = gatewaySettings.semanticProfileValue

        if browserInstallPhase == .installed {
            browserInstallPhase = .idle
        }
    }

    func openSettingsPanel() {
        appDelegate.sshConnectionsController.show(tab: .preferences)
    }

    func restartNow() {
        appDelegate.relaunchApplication()
    }

    func browseLearningWorkspace() {
        if let path = chooseDirectory(currentPath: learningChatWorkspacePath) {
            learningChatWorkspacePath = path
            learningStatusMessage = nil
        }
    }

    func browseTodoWorkspace() {
        if let path = chooseDirectory(currentPath: todoWorkspaceRootPath) {
            todoWorkspaceRootPath = path
            todoStatusMessage = nil
        }
    }

    func browseBrowserProfile() {
        if let path = appDelegate.chooseBrowserProfilePath(currentPath: browserProfilePathText) {
            browserProfilePathText = path
        }
    }

    func browseBrowserRuntime() {
        if let path = appDelegate.chooseBrowserRuntimePath(currentPath: browserRuntimePathText) {
            browserRuntimePathText = path
        }
    }

    @discardableResult
    func applySetup() -> Bool {
        learningStatusMessage = nil
        todoStatusMessage = nil
        saveFeedbackMessage = nil

        let trimmedTodoPath = todoWorkspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTodoPath.isEmpty else {
            todoStatusMessage = L10n.SSHConnections.todoWorkspaceRequired
            todoStatusTone = .danger
            saveFeedbackMessage = L10n.SSHConnections.todoWorkspaceRequired
            saveFeedbackTone = .danger
            return false
        }

        guard let gatewayPort = ControlHarnessGatewayAppSettings.parseListenPort(gatewayPortText) else {
            saveFeedbackMessage = L10n.Settings.gatewayPortInvalid
            saveFeedbackTone = .danger
            return false
        }

        let currentLearningSettings = store.learningSettings
        let trimmedChatWorkspacePath = learningChatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLearnWorkspacePath = trimmedChatWorkspacePath.isEmpty
            ? currentLearningSettings.defaultProjectPath
            : AITerminalLearningSettings.learnWorkspacePath(fromChatWorkspacePath: trimmedChatWorkspacePath)
        let resolvedNotesRelativePath = learningNotesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)

        selectedLanguage.apply()

        do {
            try appDelegate.saveMouseBackForwardTabSwitchingSetting(mouseBackForwardSwitchesTabs)
            try appDelegate.saveVisualAppIconSettings(.init(icon: builtInIconSelection))
            try appDelegate.saveBrowserSettings(
                profilePath: browserUsesManagedProfile ? "" : browserProfilePathText,
                runtimePath: browserUsesManagedRuntime ? "" : browserRuntimePathText
            )
        } catch {
            saveFeedbackMessage = error.localizedDescription
            saveFeedbackTone = .danger
            refreshBrowserRuntimeState()
            return false
        }

        store.saveLearningSettings(.init(
            enabled: learningEnabled,
            preferTabWorkingDirectory: false,
            defaultProjectPath: resolvedLearnWorkspacePath,
            notesRelativePath: resolvedNotesRelativePath,
            commandTemplate: currentLearningSettings.commandTemplate,
            fastModel: currentLearningSettings.fastModel,
            promptTemplate: currentLearningSettings.promptTemplate
        ))
        if let error = store.lastError {
            learningStatusMessage = error
            learningStatusTone = .danger
            saveFeedbackMessage = error
            saveFeedbackTone = .danger
            return false
        }

        let currentTodoSettings = store.todoSettings
        store.saveTodoSettings(.init(
            enabled: todoEnabled,
            workspaceRootPath: trimmedTodoPath,
            showCompletedItems: currentTodoSettings.showCompletedItems,
            selectedDateAnchor: currentTodoSettings.selectedDateAnchor,
            sidebarEdge: currentTodoSettings.sidebarEdge,
            workspaceOverlayVisible: currentTodoSettings.workspaceOverlayVisible,
            workspaceOverlayCorner: currentTodoSettings.workspaceOverlayCorner
        ))
        if let error = store.lastError {
            todoStatusMessage = error
            todoStatusTone = .danger
            saveFeedbackMessage = error
            saveFeedbackTone = .danger
            return false
        }

        appDelegate.saveControlHarnessGatewaySettings(.init(
            isEnabled: gatewayEnabled,
            listenHost: gatewayListenHost,
            listenPort: gatewayPort,
            pairingAdvertiseHost: gatewayPairingHost,
            showPairingQrOnLaunch: gatewayShowQrOnLaunch,
            semanticProfile: gatewaySemanticProfile.rawValue
        ))

        refreshBrowserRuntimeState()
        learningStatusMessage = L10n.SSHConnections.learningSaved
        learningStatusTone = .success
        todoStatusMessage = L10n.SSHConnections.todoSaved
        todoStatusTone = .success
        saveFeedbackMessage = needsRestart
            ? L10n.WelcomeSetup.savedRestartRequired
            : L10n.WelcomeSetup.saved
        saveFeedbackTone = needsRestart ? .warning : .success
        syncFromSources()
        return true
    }

    func finishSetup() {
        guard applySetup() else { return }
        controller?.close(nil)
    }

    func initializeLearningWorkspace() {
        guard !learningOperationInProgress else { return }
        let trimmedChatWorkspacePath = learningChatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatWorkspacePath.isEmpty else {
            learningStatusMessage = L10n.AITerminalManager.workspaceDirectoryEmpty
            learningStatusTone = .danger
            return
        }

        let commandTemplate = store.learningSettings.commandTemplate
        learningOperationInProgress = true
        learningStatusMessage = L10n.SSHConnections.learningInitializing
        learningStatusTone = .warning

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { learningOperationInProgress = false }

            guard let result = await store.initializeChatAndLearnWorkspaceAsync(
                chatWorkspacePath: trimmedChatWorkspacePath,
                commandTemplate: commandTemplate
            ) else {
                learningStatusMessage = L10n.SSHConnections.learningInitializeFailedMessage(
                    store.lastError ?? "unknown"
                )
                learningStatusTone = .danger
                return
            }

            learningChatWorkspacePath = result.chatWorkspacePath
            learningNotesRelativePath = store.learningSettings.notesRelativePath
            learningStatusMessage = L10n.SSHConnections.learningInitializedMessage(
                result.createdFileCount,
                result.reusedFileCount
            )
            learningStatusTone = .success
        }
    }

    func initializeTodoWorkspace() {
        let trimmedRootPath = todoWorkspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRootPath.isEmpty else {
            todoStatusMessage = L10n.SSHConnections.todoWorkspaceRequired
            todoStatusTone = .danger
            return
        }

        guard let result = store.initializeTodoWorkspace(rootPath: trimmedRootPath) else {
            todoStatusMessage = L10n.SSHConnections.todoInitializeFailedMessage(
                store.lastError ?? "unknown"
            )
            todoStatusTone = .danger
            return
        }

        todoWorkspaceRootPath = result.workspaceRootPath
        todoStatusMessage = L10n.SSHConnections.todoInitializedMessage(
            result.createdFileCount,
            result.reusedFileCount
        )
        todoStatusTone = .success
    }

    func installManagedBrowserRuntime() {
        guard canInstallManagedRuntime else { return }
        browserInstallTask?.cancel()
        browserInstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await BrowserRuntimeInstaller.install { [weak self] phase in
                    self?.browserInstallPhase = phase
                }

                if GhoDexCEFInitializeGlobal() {
                    browserInstallPhase = .installed
                } else {
                    browserInstallPhase = .failed(L10n.WelcomeSetup.browserRuntimeActivationFailed)
                }
            } catch {
                browserInstallPhase = .failed(error.localizedDescription)
            }

            refreshBrowserRuntimeState()
        }
    }

    func retryBrowserRuntimeActivation() {
        guard canRetryBrowserActivation else { return }
        _ = GhoDexCEFInitializeGlobal()
        refreshBrowserRuntimeState()
    }

    func iconDisplayName(_ icon: Ghostty.MacOSIcon) -> String {
        switch icon {
        case .official:
            return L10n.Settings.iconOptionOfficial
        case .ghodex:
            return L10n.Settings.iconOptionGhodex
        case .banana:
            return L10n.Settings.iconOptionBanana
        case .blueprint:
            return L10n.Settings.iconOptionBlueprint
        case .chalkboard:
            return L10n.Settings.iconOptionChalkboard
        case .glass:
            return L10n.Settings.iconOptionGlass
        case .holographic:
            return L10n.Settings.iconOptionHolographic
        case .microchip:
            return L10n.Settings.iconOptionMicrochip
        case .paper:
            return L10n.Settings.iconOptionPaper
        case .retro:
            return L10n.Settings.iconOptionRetro
        case .xray:
            return L10n.Settings.iconOptionXray
        case .custom, .customStyle:
            return L10n.Settings.iconOptionOfficial
        }
    }

    func previewImage(for icon: Ghostty.MacOSIcon) -> NSImage {
        AppIconSettings(icon: icon).previewImage(in: .main) ?? previewIconImage
    }

    private func refreshBrowserRuntimeState() {
        if !GhoDexCEFBuildSupportsManagedRuntime() {
            browserRuntimeState = .unsupportedBuild
        } else if GhoDexCEFIsInitialized() {
            browserRuntimeState = .ready
        } else if GhoDexCEFIsInitializing() {
            browserRuntimeState = .initializing
        } else if GhoDexCEFBuildHasRuntime() {
            browserRuntimeState = .initializationFailed
        } else {
            browserRuntimeState = .unavailable
        }
    }

    private func chooseDirectory(currentPath: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Settings.browserBrowseButton

        let trimmedPath = currentPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPath.isEmpty {
            let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
                .deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url.path
    }
}
