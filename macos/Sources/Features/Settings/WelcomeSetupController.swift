import AppKit
import SwiftUI

@MainActor
final class WelcomeSetupController: NSWindowController, NSWindowDelegate {
    let model: WelcomeSetupModel
    private unowned let appDelegate: AppDelegate
    private weak var parentWindow: NSWindow?
    private var overlayHostingView: NonDraggableHostingView<AnyView>?
    private var parentWindowCloseObserver: NSObjectProtocol?
    private var pendingParentWindowObserver: NSObjectProtocol?

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
        window.setContentSize(NSSize(width: 980, height: 780))
        window.minSize = NSSize(width: 900, height: 720)

        super.init(window: window)
        self.window?.delegate = self
        self.model.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo preferredParentWindow: NSWindow? = nil) {
        guard let window else { return }
        model.syncFromSources()
        window.title = L10n.WelcomeSetup.windowTitle
        window.contentViewController = NSHostingController(rootView: welcomeContentView())

        let resolvedParentWindow = resolvedParentWindow(from: preferredParentWindow)
        if resolvedParentWindow !== parentWindow {
            detachOverlayIfNeeded()
            parentWindow = resolvedParentWindow
        }

        if let resolvedParentWindow {
            showOverlay(in: resolvedParentWindow)
        } else {
            detachOverlayIfNeeded()
            queueOverlayPresentationWhenParentWindowBecomesAvailable()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func close(_ sender: Any?) {
        guard let window else { return }

        if overlayHostingView != nil {
            detachOverlayIfNeeded()
            return
        }

        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
            return
        }

        window.performClose(sender)
    }

    @objc func cancel(_ sender: Any?) {
        close(sender)
    }

    func windowWillClose(_ notification: Notification) {
        detachOverlayIfNeeded()
    }

    private func resolvedParentWindow(from preferredParentWindow: NSWindow?) -> NSWindow? {
        let candidates = [
            preferredParentWindow,
            NSApp.keyWindow,
            NSApp.mainWindow,
        ] + NSApp.orderedWindows

        return candidates.lazy.compactMap(resolvedTopLevelWindow(from:)).first
    }

    private func showOverlay(in parentWindow: NSWindow) {
        guard let contentView = parentWindow.contentView else { return }

        window?.orderOut(nil)
        removePendingParentWindowObserver()

        let hostingView: NonDraggableHostingView<AnyView>
        if let existing = overlayHostingView {
            hostingView = existing
            hostingView.rootView = overlayRootView()
        } else {
            hostingView = NonDraggableHostingView(rootView: overlayRootView())
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            overlayHostingView = hostingView
        }

        if hostingView.superview !== contentView {
            hostingView.removeFromSuperview()
            contentView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        installParentWindowObserver(for: parentWindow)
        parentWindow.makeKeyAndOrderFront(nil)
    }

    private func detachOverlayIfNeeded() {
        overlayHostingView?.removeFromSuperview()
        overlayHostingView = nil
        removeParentWindowObserver()
    }

    private func installParentWindowObserver(for parentWindow: NSWindow) {
        removeParentWindowObserver()
        parentWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detachOverlayIfNeeded()
                self?.parentWindow = nil
            }
        }
    }

    private func removeParentWindowObserver() {
        if let parentWindowCloseObserver {
            NotificationCenter.default.removeObserver(parentWindowCloseObserver)
            self.parentWindowCloseObserver = nil
        }
    }

    private func queueOverlayPresentationWhenParentWindowBecomesAvailable() {
        guard pendingParentWindowObserver == nil else { return }

        pendingParentWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let candidate = self.resolvedParentWindow(from: notification.object as? NSWindow) else {
                    return
                }

                self.parentWindow = candidate
                self.showOverlay(in: candidate)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let candidate = self.resolvedParentWindow(from: nil) else { return }
            self.parentWindow = candidate
            self.showOverlay(in: candidate)
        }
    }

    private func removePendingParentWindowObserver() {
        if let pendingParentWindowObserver {
            NotificationCenter.default.removeObserver(pendingParentWindowObserver)
            self.pendingParentWindowObserver = nil
        }
    }

    private func resolvedTopLevelWindow(from candidate: NSWindow?) -> NSWindow? {
        guard var candidate else { return nil }

        while let sheetParent = candidate.sheetParent {
            candidate = sheetParent
        }

        while let parent = candidate.parent {
            candidate = parent
        }

        guard candidate !== window else { return nil }
        return candidate
    }

    private func welcomeContentView() -> some View {
        WelcomeSetupView(model: model)
            .environmentObject(appDelegate)
    }

    private func overlayRootView() -> AnyView {
        AnyView(
            WelcomeSetupOverlayView(
                content: AnyView(welcomeContentView()),
                onClose: { [weak self] in
                    self?.close(nil)
                }
            )
        )
    }
}

private struct WelcomeSetupOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: AnyView
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 24
            let availableWidth = max(360, geometry.size.width - (inset * 2))
            let availableHeight = max(420, geometry.size.height - (inset * 2))
            let contentWidth = min(980, availableWidth)
            let contentHeight = min(780, availableHeight)

            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.46 : 0.22)
                    .ignoresSafeArea()

                ZStack(alignment: .topTrailing) {
                    content
                        .frame(width: contentWidth, height: contentHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(
                                    Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.28 : 0.12),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.14), radius: 36, y: 18)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.9 : 0.96))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
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

    enum Step: Int, CaseIterable, Identifiable {
        case workspace
        case app
        case browser
        case gateway

        var id: Int { rawValue }
    }

    enum BrowserRuntimeState {
        case ready
        case unsupportedBuild
        case initializing
        case initializationFailed
        case unavailable
    }

    struct WorkspacePathPreview: Identifiable {
        let id: String
        let title: String
        let path: String
    }

    struct FeatureGuideItem: Identifiable {
        let id: String
        let step: Step
        let iconSystemName: String
        let title: String
        let summary: String
        let usage: String
    }

    private static let workspaceContainerDirectoryName = ".ghodex"
    private static let workspaceDirectoryName = "workspace"
    private static let browserDirectoryName = "browser"
    private static let browserProfileDirectoryName = "profile"
    private static let browserRuntimeDirectoryName = "runtime"

    weak var controller: WelcomeSetupController?

    private unowned let appDelegate: AppDelegate
    private let store: AITerminalManagerStore
    private var browserInstallTask: Task<Void, Never>?
    private var workspacePreparationTask: Task<Void, Never>?

    @Published var currentStep: Step = .workspace
    @Published var ghodexWorkspaceRootPath = WelcomeSetupModel.defaultWorkspaceRootPath
    @Published var showAdvancedPaths = false

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

    @Published var browserUsesManagedProfile = false
    @Published var browserProfilePathText = ""
    @Published var browserUsesManagedRuntime = false
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

    @Published var workspaceStatusMessage: String?
    @Published var workspaceStatusTone: StatusTone = .neutral

    init(appDelegate: AppDelegate, store: AITerminalManagerStore) {
        self.appDelegate = appDelegate
        self.store = store
        syncFromSources()
    }

    static var defaultWorkspaceRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(workspaceContainerDirectoryName, isDirectory: true)
            .appendingPathComponent(workspaceDirectoryName, isDirectory: true)
            .path
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

    var orderedSteps: [Step] {
        Step.allCases
    }

    var currentStepIndex: Int {
        orderedSteps.firstIndex(of: currentStep) ?? 0
    }

    var canGoBack: Bool {
        currentStepIndex > 0
    }

    var isLastStep: Bool {
        currentStepIndex == orderedSteps.count - 1
    }

    var currentStepTitle: String {
        title(for: currentStep)
    }

    var currentStepBody: String {
        body(for: currentStep)
    }

    var stepProgressText: String {
        L10n.WelcomeSetup.stepProgress(currentStepIndex + 1, orderedSteps.count)
    }

    var resolvedWorkspaceRootPath: String {
        let trimmed = ghodexWorkspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.defaultWorkspaceRootPath
        }

        return NSString(string: trimmed).expandingTildeInPath
    }

    var defaultLearningChatWorkspacePath: String {
        Self.defaultLearningChatWorkspacePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    var resolvedLearningChatWorkspacePath: String {
        guard showAdvancedPaths else {
            return defaultLearningChatWorkspacePath
        }

        return resolvedDirectoryOverride(
            learningChatWorkspacePath,
            fallback: defaultLearningChatWorkspacePath
        )
    }

    var resolvedLearnWorkspacePath: String {
        AITerminalLearningSettings.learnWorkspacePath(fromChatWorkspacePath: resolvedLearningChatWorkspacePath)
    }

    var defaultTodoWorkspacePath: String {
        Self.defaultTodoWorkspacePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    var resolvedTodoWorkspacePath: String {
        guard showAdvancedPaths else {
            return defaultTodoWorkspacePath
        }

        return resolvedDirectoryOverride(
            todoWorkspaceRootPath,
            fallback: defaultTodoWorkspacePath
        )
    }

    var defaultBrowserProfilePath: String {
        Self.defaultBrowserProfilePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    var resolvedBrowserProfilePath: String {
        guard showAdvancedPaths else {
            return defaultBrowserProfilePath
        }

        return resolvedDirectoryOverride(
            browserProfilePathText,
            fallback: defaultBrowserProfilePath
        )
    }

    var defaultBrowserRuntimePath: String {
        Self.defaultBrowserRuntimePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    var resolvedBrowserRuntimePath: String {
        guard showAdvancedPaths else {
            return defaultBrowserRuntimePath
        }

        return resolvedDirectoryOverride(
            browserRuntimePathText,
            fallback: defaultBrowserRuntimePath
        )
    }

    var usesDerivedWorkspacePaths: Bool {
        !showAdvancedPaths
    }

    var resolvedNotesAbsolutePath: String {
        let resolvedNotesPath = resolvedNotesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotesPath = resolvedNotesPath.isEmpty
            ? AITerminalLearningSettings.defaultNotesRelativePath
            : resolvedNotesPath

        if normalizedNotesPath.hasPrefix("/") {
            return normalizedNotesPath
        }

        return URL(fileURLWithPath: resolvedLearnWorkspacePath, isDirectory: true)
            .appendingPathComponent(normalizedNotesPath, isDirectory: false)
            .path
    }

    var resolvedNotesRelativePath: String {
        let trimmed = learningNotesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if showAdvancedPaths, !trimmed.isEmpty {
            return trimmed
        }

        return AITerminalLearningSettings.defaultNotesRelativePath
    }

    var defaultWorkspaceRootHint: String {
        L10n.WelcomeSetup.workspaceRootDefaultHint(Self.defaultWorkspaceRootPath)
    }

    var currentStepFeatureGuides: [FeatureGuideItem] {
        featureGuideItems.filter { $0.step == currentStep }
    }

    // Central onboarding registry. New features only need one item here to
    // join the guided setup flow with a title, explanation, and usage hint.
    var featureGuideItems: [FeatureGuideItem] {
        [
            .init(
                id: "chat",
                step: .workspace,
                iconSystemName: "message.badge.waveform.fill",
                title: L10n.WelcomeSetup.guideChatTitle,
                summary: L10n.WelcomeSetup.guideChatSummary,
                usage: L10n.WelcomeSetup.guideChatUsage
            ),
            .init(
                id: "learn",
                step: .workspace,
                iconSystemName: "brain.head.profile",
                title: L10n.WelcomeSetup.guideLearnTitle,
                summary: L10n.WelcomeSetup.guideLearnSummary,
                usage: L10n.WelcomeSetup.guideLearnUsage
            ),
            .init(
                id: "todo",
                step: .workspace,
                iconSystemName: "checklist.checked",
                title: L10n.WelcomeSetup.guideTodoTitle,
                summary: L10n.WelcomeSetup.guideTodoSummary,
                usage: L10n.WelcomeSetup.guideTodoUsage
            ),
            .init(
                id: "browser",
                step: .workspace,
                iconSystemName: "globe.badge.chevron.backward",
                title: L10n.WelcomeSetup.guideBrowserTitle,
                summary: L10n.WelcomeSetup.guideBrowserSummary,
                usage: L10n.WelcomeSetup.guideBrowserUsage
            ),
            .init(
                id: "app",
                step: .app,
                iconSystemName: "switch.2",
                title: L10n.WelcomeSetup.guideAppTitle,
                summary: L10n.WelcomeSetup.guideAppSummary,
                usage: L10n.WelcomeSetup.guideAppUsage
            ),
            .init(
                id: "browser_runtime",
                step: .browser,
                iconSystemName: "shippingbox.fill",
                title: L10n.WelcomeSetup.guideBrowserRuntimeTitle,
                summary: L10n.WelcomeSetup.guideBrowserRuntimeSummary,
                usage: L10n.WelcomeSetup.guideBrowserRuntimeUsage
            ),
            .init(
                id: "gateway",
                step: .gateway,
                iconSystemName: "point.3.connected.trianglepath.dotted",
                title: L10n.WelcomeSetup.guideGatewayTitle,
                summary: L10n.WelcomeSetup.guideGatewaySummary,
                usage: L10n.WelcomeSetup.guideGatewayUsage
            ),
        ]
    }

    var workspacePathPreviews: [WorkspacePathPreview] {
        [
            .init(id: "chat", title: L10n.WelcomeSetup.workspacePreviewChat, path: resolvedLearningChatWorkspacePath),
            .init(id: "learn", title: L10n.WelcomeSetup.workspacePreviewLearn, path: resolvedLearnWorkspacePath),
            .init(id: "notes", title: L10n.WelcomeSetup.workspacePreviewNotes, path: resolvedNotesAbsolutePath),
            .init(id: "todo", title: L10n.WelcomeSetup.workspacePreviewTodo, path: resolvedTodoWorkspacePath),
            .init(id: "browser_profile", title: L10n.WelcomeSetup.workspacePreviewBrowserProfile, path: resolvedBrowserProfilePath),
            .init(id: "browser_runtime", title: L10n.WelcomeSetup.workspacePreviewBrowserRuntime, path: resolvedBrowserRuntimePath),
        ]
    }

    var browserRuntimeAssessment: BrowserRuntimeMediaAssessment {
        BrowserPaths.runtimeMediaAssessment(
            runtimePath: resolvedBrowserRuntimePath,
            usesManagedRuntime: false
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

    var canInstallManagedRuntime: Bool {
        browserRuntimeState != .ready &&
            browserRuntimeState != .unsupportedBuild &&
            !browserInstallPhase.isWorking
    }

    var canRetryBrowserActivation: Bool {
        browserRuntimeState != .ready &&
            browserRuntimeState != .unsupportedBuild &&
            !browserInstallPhase.isWorking
    }

    var isBusy: Bool {
        learningOperationInProgress || browserInstallPhase.isWorking || workspacePreparationTask != nil
    }

    func syncFromSources() {
        selectedLanguage = AppLanguageSetting.storedSelection()
        mouseBackForwardSwitchesTabs = appDelegate.mouseBackForwardSwitchesTabs
        builtInIconSelection = appDelegate.appIconSettings.sanitized.icon

        let learningSettings = store.learningSettings
        learningEnabled = learningSettings.enabled
        let currentChatWorkspacePath = AITerminalLearningSettings.chatWorkspacePath(
            fromLearnWorkspacePath: learningSettings.defaultProjectPath
        )

        let todoSettings = store.todoSettings
        todoEnabled = todoSettings.enabled

        let currentProfilePath = appDelegate.browserProfilePathOverride ?? ""
        let currentRuntimePath = appDelegate.browserRuntimePathOverride ?? ""

        let inferredWorkspaceRoot = Self.inferWorkspaceRootPath(
            chatWorkspacePath: currentChatWorkspacePath,
            todoWorkspacePath: todoSettings.workspaceRootPath,
            browserProfilePath: currentProfilePath,
            browserRuntimePath: currentRuntimePath
        ) ?? Self.defaultWorkspaceRootPath

        let effectiveChatPath = currentChatWorkspacePath.isEmpty
            ? Self.defaultLearningChatWorkspacePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentChatWorkspacePath
        let effectiveTodoPath = todoSettings.workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultTodoWorkspacePath(workspaceRootPath: inferredWorkspaceRoot)
            : todoSettings.workspaceRootPath
        let effectiveProfilePath = currentProfilePath.isEmpty
            ? Self.defaultBrowserProfilePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentProfilePath
        let effectiveRuntimePath = currentRuntimePath.isEmpty
            ? Self.defaultBrowserRuntimePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentRuntimePath

        ghodexWorkspaceRootPath = inferredWorkspaceRoot
        learningChatWorkspacePath = effectiveChatPath
        learningNotesRelativePath = learningSettings.notesRelativePath
        todoWorkspaceRootPath = effectiveTodoPath
        browserProfilePathText = effectiveProfilePath
        browserRuntimePathText = effectiveRuntimePath
        browserUsesManagedProfile = false
        browserUsesManagedRuntime = false
        showAdvancedPaths = !Self.usesDefaultWorkspaceLayout(
            workspaceRootPath: inferredWorkspaceRoot,
            chatWorkspacePath: effectiveChatPath,
            notesRelativePath: learningSettings.notesRelativePath,
            todoWorkspacePath: effectiveTodoPath,
            browserProfilePath: effectiveProfilePath,
            browserRuntimePath: effectiveRuntimePath
        )
        refreshBrowserRuntimeState()

        let gatewaySettings = appDelegate.controlHarnessGatewaySettings
        gatewayEnabled = gatewaySettings.isEnabled
        gatewayListenHost = gatewaySettings.listenHost
        gatewayPortText = String(gatewaySettings.listenPort)
        gatewayPairingHost = gatewaySettings.pairingAdvertiseHost
        gatewayShowQrOnLaunch = gatewaySettings.showPairingQrOnLaunch
        gatewaySemanticProfile = gatewaySettings.semanticProfileValue

        currentStep = .workspace
        workspaceStatusMessage = nil
        workspaceStatusTone = .neutral
        saveFeedbackMessage = nil
        saveFeedbackTone = .neutral

        if browserInstallPhase == .installed {
            browserInstallPhase = .idle
        }
    }

    func goToNextStep() {
        guard !isLastStep else { return }
        currentStep = orderedSteps[currentStepIndex + 1]
    }

    func goToPreviousStep() {
        guard canGoBack else { return }
        currentStep = orderedSteps[currentStepIndex - 1]
    }

    func openSettingsPanel() {
        appDelegate.sshConnectionsController.show(tab: .preferences)
    }

    func restartNow() {
        appDelegate.relaunchApplication()
    }

    func browseWorkspaceRoot() {
        if let path = chooseDirectory(currentPath: ghodexWorkspaceRootPath) {
            ghodexWorkspaceRootPath = path
            workspaceStatusMessage = nil
        }
    }

    func browseLearningWorkspace() {
        if let path = chooseDirectory(currentPath: learningChatWorkspacePath) {
            showAdvancedPaths = true
            learningChatWorkspacePath = path
            learningStatusMessage = nil
        }
    }

    func browseTodoWorkspace() {
        if let path = chooseDirectory(currentPath: todoWorkspaceRootPath) {
            showAdvancedPaths = true
            todoWorkspaceRootPath = path
            todoStatusMessage = nil
        }
    }

    func browseBrowserProfile() {
        if let path = appDelegate.chooseBrowserProfilePath(currentPath: browserProfilePathText) {
            showAdvancedPaths = true
            browserProfilePathText = path
        }
    }

    func browseBrowserRuntime() {
        if let path = appDelegate.chooseBrowserRuntimePath(currentPath: browserRuntimePathText) {
            showAdvancedPaths = true
            browserRuntimePathText = path
        }
    }

    @discardableResult
    func applySetup() -> Bool {
        learningStatusMessage = nil
        todoStatusMessage = nil
        workspaceStatusMessage = nil
        saveFeedbackMessage = nil

        guard let gatewayPort = ControlHarnessGatewayAppSettings.parseListenPort(gatewayPortText) else {
            saveFeedbackMessage = L10n.Settings.gatewayPortInvalid
            saveFeedbackTone = .danger
            return false
        }

        let currentLearningSettings = store.learningSettings
        let currentTodoSettings = store.todoSettings
        let resolvedChatWorkspacePath = resolvedLearningChatWorkspacePath
        let resolvedLearnWorkspacePath = resolvedLearnWorkspacePath
        let resolvedNotesRelativePath = resolvedNotesRelativePath
        let resolvedTodoWorkspacePath = resolvedTodoWorkspacePath
        let resolvedBrowserProfilePath = resolvedBrowserProfilePath
        let resolvedBrowserRuntimePath = resolvedBrowserRuntimePath

        selectedLanguage.apply()

        do {
            try ensureWorkspaceDirectoriesExist(
                profilePath: resolvedBrowserProfilePath,
                runtimePath: resolvedBrowserRuntimePath
            )
            try appDelegate.saveMouseBackForwardTabSwitchingSetting(mouseBackForwardSwitchesTabs)
            try appDelegate.saveVisualAppIconSettings(.init(icon: builtInIconSelection))
            try appDelegate.saveBrowserSettings(
                profilePath: resolvedBrowserProfilePath,
                runtimePath: resolvedBrowserRuntimePath
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

        learningChatWorkspacePath = resolvedChatWorkspacePath

        store.saveTodoSettings(.init(
            enabled: todoEnabled,
            workspaceRootPath: resolvedTodoWorkspacePath,
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

        todoWorkspaceRootPath = resolvedTodoWorkspacePath

        appDelegate.saveControlHarnessGatewaySettings(.init(
            isEnabled: gatewayEnabled,
            listenHost: gatewayListenHost,
            listenPort: gatewayPort,
            pairingAdvertiseHost: gatewayPairingHost,
            showPairingQrOnLaunch: gatewayShowQrOnLaunch,
            semanticProfile: gatewaySemanticProfile.rawValue
        ))

        refreshBrowserRuntimeState()
        saveFeedbackMessage = needsRestart
            ? L10n.WelcomeSetup.savedRestartRequired
            : L10n.WelcomeSetup.saved
        saveFeedbackTone = needsRestart ? .warning : .success
        return true
    }

    func finishSetup() {
        guard applySetup() else { return }
        controller?.close(nil)
    }

    func prepareWorkspaceLayout() {
        guard workspacePreparationTask == nil else { return }
        guard applySetup() else { return }

        let chatWorkspacePath = resolvedLearningChatWorkspacePath
        let todoWorkspacePath = resolvedTodoWorkspacePath
        let commandTemplate = store.learningSettings.commandTemplate

        workspaceStatusMessage = L10n.WelcomeSetup.workspacePreparing
        workspaceStatusTone = .warning

        workspacePreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { workspacePreparationTask = nil }

            do {
                try ensureWorkspaceDirectoriesExist(
                    profilePath: resolvedBrowserProfilePath,
                    runtimePath: resolvedBrowserRuntimePath
                )
            } catch {
                workspaceStatusMessage = error.localizedDescription
                workspaceStatusTone = .danger
                return
            }

            if learningEnabled {
                learningOperationInProgress = true
                defer { learningOperationInProgress = false }

                guard let learningResult = await store.initializeChatAndLearnWorkspaceAsync(
                    chatWorkspacePath: chatWorkspacePath,
                    commandTemplate: commandTemplate
                ) else {
                    let message = L10n.SSHConnections.learningInitializeFailedMessage(
                        store.lastError ?? "unknown"
                    )
                    learningStatusMessage = message
                    learningStatusTone = .danger
                    workspaceStatusMessage = message
                    workspaceStatusTone = .danger
                    return
                }

                learningChatWorkspacePath = learningResult.chatWorkspacePath
                learningNotesRelativePath = store.learningSettings.notesRelativePath
                learningStatusMessage = L10n.SSHConnections.learningInitializedMessage(
                    learningResult.createdFileCount,
                    learningResult.reusedFileCount
                )
                learningStatusTone = .success
            }

            if todoEnabled {
                guard let todoResult = store.initializeTodoWorkspace(rootPath: todoWorkspacePath) else {
                    let message = L10n.SSHConnections.todoInitializeFailedMessage(
                        store.lastError ?? "unknown"
                    )
                    todoStatusMessage = message
                    todoStatusTone = .danger
                    workspaceStatusMessage = message
                    workspaceStatusTone = .danger
                    return
                }

                todoWorkspaceRootPath = todoResult.workspaceRootPath
                todoStatusMessage = L10n.SSHConnections.todoInitializedMessage(
                    todoResult.createdFileCount,
                    todoResult.reusedFileCount
                )
                todoStatusTone = .success
            }

            workspaceStatusMessage = L10n.WelcomeSetup.workspacePrepared
            workspaceStatusTone = .success
        }
    }

    func initializeLearningWorkspace() {
        guard !learningOperationInProgress else { return }
        guard applySetup() else { return }

        let chatWorkspacePath = resolvedLearningChatWorkspacePath
        let commandTemplate = store.learningSettings.commandTemplate
        learningOperationInProgress = true
        learningStatusMessage = L10n.SSHConnections.learningInitializing
        learningStatusTone = .warning

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { learningOperationInProgress = false }

            guard let result = await store.initializeChatAndLearnWorkspaceAsync(
                chatWorkspacePath: chatWorkspacePath,
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
        guard applySetup() else { return }

        let rootPath = resolvedTodoWorkspacePath
        guard let result = store.initializeTodoWorkspace(rootPath: rootPath) else {
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
        guard applySetup() else { return }

        let destinationRuntimeRoot = URL(
            fileURLWithPath: resolvedBrowserRuntimePath,
            isDirectory: true
        )

        browserInstallTask?.cancel()
        browserInstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { browserInstallTask = nil }

            do {
                try await BrowserRuntimeInstaller.install(
                    destinationRuntimeRoot: destinationRuntimeRoot
                ) { [weak self] phase in
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

    func title(for step: Step) -> String {
        switch step {
        case .workspace:
            return L10n.WelcomeSetup.workspaceSectionTitle
        case .app:
            return L10n.WelcomeSetup.appSectionTitle
        case .browser:
            return L10n.WelcomeSetup.browserSectionTitle
        case .gateway:
            return L10n.WelcomeSetup.gatewaySectionTitle
        }
    }

    func body(for step: Step) -> String {
        switch step {
        case .workspace:
            return L10n.WelcomeSetup.workspaceSectionBody
        case .app:
            return L10n.WelcomeSetup.appSectionBody
        case .browser:
            return L10n.WelcomeSetup.browserSectionBody
        case .gateway:
            return L10n.WelcomeSetup.gatewaySectionBody
        }
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

    private func ensureWorkspaceDirectoriesExist(
        profilePath: String,
        runtimePath: String
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: resolvedWorkspaceRootPath, isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: profilePath, isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: runtimePath, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func resolvedDirectoryOverride(
        _ candidate: String,
        fallback: String
    ) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func defaultLearningChatWorkspacePath(workspaceRootPath: String) -> String {
        URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(AITerminalLearningSettings.chatWorkspaceDirectoryName, isDirectory: true)
            .path
    }

    private static func defaultTodoWorkspacePath(workspaceRootPath: String) -> String {
        URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(AITerminalTodoSettings.workspaceDirectoryName, isDirectory: true)
            .path
    }

    private static func defaultBrowserProfilePath(workspaceRootPath: String) -> String {
        URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(browserDirectoryName, isDirectory: true)
            .appendingPathComponent(browserProfileDirectoryName, isDirectory: true)
            .path
    }

    private static func defaultBrowserRuntimePath(workspaceRootPath: String) -> String {
        URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(browserDirectoryName, isDirectory: true)
            .appendingPathComponent(browserRuntimeDirectoryName, isDirectory: true)
            .path
    }

    private static func inferWorkspaceRootPath(
        chatWorkspacePath: String,
        todoWorkspacePath: String,
        browserProfilePath: String,
        browserRuntimePath: String
    ) -> String? {
        for candidate in [
            workspaceRootCandidate(fromBrowserProfilePath: browserProfilePath),
            workspaceRootCandidate(fromBrowserRuntimePath: browserRuntimePath),
            workspaceRootCandidate(fromTodoWorkspacePath: todoWorkspacePath),
            workspaceRootCandidate(fromChatWorkspacePath: chatWorkspacePath),
        ] {
            if let candidate {
                return candidate
            }
        }

        return nil
    }

    private static func usesDefaultWorkspaceLayout(
        workspaceRootPath: String,
        chatWorkspacePath: String,
        notesRelativePath: String,
        todoWorkspacePath: String,
        browserProfilePath: String,
        browserRuntimePath: String
    ) -> Bool {
        normalizedDirectoryPath(chatWorkspacePath) == normalizedDirectoryPath(
            defaultLearningChatWorkspacePath(workspaceRootPath: workspaceRootPath)
        ) &&
        normalizedDirectoryPath(todoWorkspacePath) == normalizedDirectoryPath(
            defaultTodoWorkspacePath(workspaceRootPath: workspaceRootPath)
        ) &&
        normalizedDirectoryPath(browserProfilePath) == normalizedDirectoryPath(
            defaultBrowserProfilePath(workspaceRootPath: workspaceRootPath)
        ) &&
        normalizedDirectoryPath(browserRuntimePath) == normalizedDirectoryPath(
            defaultBrowserRuntimePath(workspaceRootPath: workspaceRootPath)
        ) &&
        normalizedNotesPath(notesRelativePath) == normalizedNotesPath(
            AITerminalLearningSettings.defaultNotesRelativePath
        )
    }

    private static func workspaceRootCandidate(fromChatWorkspacePath path: String) -> String? {
        guard var url = normalizedDirectoryURL(path) else { return nil }
        guard url.lastPathComponent == AITerminalLearningSettings.chatWorkspaceDirectoryName else {
            return nil
        }
        url.deleteLastPathComponent()
        return url.path
    }

    private static func workspaceRootCandidate(fromTodoWorkspacePath path: String) -> String? {
        guard var url = normalizedDirectoryURL(path) else { return nil }
        guard url.lastPathComponent == AITerminalTodoSettings.workspaceDirectoryName else {
            return nil
        }
        url.deleteLastPathComponent()
        return url.path
    }

    private static func workspaceRootCandidate(fromBrowserProfilePath path: String) -> String? {
        guard var url = normalizedDirectoryURL(path) else { return nil }
        guard url.lastPathComponent == browserProfileDirectoryName else { return nil }
        url.deleteLastPathComponent()
        guard url.lastPathComponent == browserDirectoryName else { return nil }
        url.deleteLastPathComponent()
        return url.path
    }

    private static func workspaceRootCandidate(fromBrowserRuntimePath path: String) -> String? {
        guard var url = normalizedDirectoryURL(path) else { return nil }
        guard url.lastPathComponent == browserRuntimeDirectoryName else { return nil }
        url.deleteLastPathComponent()
        guard url.lastPathComponent == browserDirectoryName else { return nil }
        url.deleteLastPathComponent()
        return url.path
    }

    private static func normalizedDirectoryPath(_ path: String) -> String? {
        normalizedDirectoryURL(path)?.path
    }

    private static func normalizedDirectoryURL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private static func normalizedNotesPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AITerminalLearningSettings.defaultNotesRelativePath : trimmed
    }
}
