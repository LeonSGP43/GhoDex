import AppKit
import Foundation

@MainActor
final class BrowserPageState: ObservableObject, Identifiable {
    let id = UUID()
    let initialURL: URL

    @Published private(set) var pageTitle: String
    @Published private(set) var displayedURL: String
    @Published var addressText: String
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false

    fileprivate var onStateChange: (() -> Void)?
    fileprivate var isAddressBarEditing = false

    private var loadURLHandler: ((String) -> Void)?
    private var goBackHandler: (() -> Void)?
    private var goForwardHandler: (() -> Void)?
    private var reloadHandler: (() -> Void)?

    init(initialURL: URL) {
        self.initialURL = initialURL
        let initial = initialURL.absoluteString
        self.pageTitle = initial
        self.displayedURL = initial
        self.addressText = initial
    }

    var tabTitle: String {
        if pageTitle == displayedURL || pageTitle.isEmpty {
            return displayedURL
        }
        return pageTitle
    }

    var restorableURL: URL {
        URL(string: displayedURL) ?? initialURL
    }

    func submitAddress(normalize: (String, String?) -> String) {
        let normalized = normalize(addressText, initialURL.absoluteString)
        isAddressBarEditing = false
        addressText = normalized
        loadURLHandler?(normalized)
        onStateChange?()
    }

    func setAddressBarEditing(_ isEditing: Bool) {
        isAddressBarEditing = isEditing
    }

    func updateAddressText(_ text: String) {
        addressText = text
        onStateChange?()
    }

    func goBack() {
        goBackHandler?()
    }

    func goForward() {
        goForwardHandler?()
    }

    func reload() {
        reloadHandler?()
    }

    func bindBridge(
        loadURL: @escaping (String) -> Void,
        goBack: @escaping () -> Void,
        goForward: @escaping () -> Void,
        reload: @escaping () -> Void
    ) {
        loadURLHandler = loadURL
        goBackHandler = goBack
        goForwardHandler = goForward
        reloadHandler = reload
    }

    func unbindBridge() {
        loadURLHandler = nil
        goBackHandler = nil
        goForwardHandler = nil
        reloadHandler = nil
    }

    func updatePageState(
        title: String?,
        url: String?,
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool
    ) {
        if let title, !title.isEmpty {
            pageTitle = title
        } else if let url, !url.isEmpty {
            pageTitle = url
        }

        if let url, !url.isEmpty {
            displayedURL = url
            if !isAddressBarEditing {
                addressText = url
            }
        }

        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        onStateChange?()
    }
}

@MainActor
final class BrowserTabModel: ObservableObject {
    enum RuntimeState: Equatable {
        case ready
        case unsupportedBuild
        case runtimeUnavailable
        case initializationFailed
    }

    @Published private(set) var pages: [BrowserPageState]
    @Published private(set) var selectedPageID: UUID
    @Published var pageTitle: String = AppLocalization.localizedText("Browser")
    @Published var displayedURL: String
    @Published var addressText: String
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published private(set) var runtimeState: RuntimeState
    @Published private(set) var installPhase: BrowserRuntimeInstallPhase = .idle

    private let defaultPageURL: URL
    private var installTask: Task<Void, Never>?

    init(initialURL: URL) {
        self.defaultPageURL = initialURL
        let initialPage = BrowserPageState(initialURL: initialURL)
        self.pages = [initialPage]
        self.selectedPageID = initialPage.id
        self.displayedURL = initialURL.absoluteString
        self.addressText = initialURL.absoluteString
        self.runtimeState = .runtimeUnavailable
        register(page: initialPage)
        refreshRuntimeState()
        syncActivePageState()
    }

    deinit {
        installTask?.cancel()
    }

    var activePage: BrowserPageState? {
        pages.first(where: { $0.id == selectedPageID }) ?? pages.first
    }

    func isSelected(_ page: BrowserPageState) -> Bool {
        page.id == selectedPageID
    }

    func selectPage(_ pageID: UUID) {
        guard pages.contains(where: { $0.id == pageID }) else { return }
        selectedPageID = pageID
        syncActivePageState()
    }

    func newPageTab() {
        appendPage(initialURL: defaultPageURL, activate: true)
    }

    func closePage(_ pageID: UUID) {
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let closingSelectedPage = selectedPageID == pageID
        pages.remove(at: index)

        if closingSelectedPage {
            let replacementIndex = min(index, pages.count - 1)
            selectedPageID = pages[replacementIndex].id
        }

        syncActivePageState()
    }

    func bindBridge(
        for pageID: UUID,
        loadURL: @escaping (String) -> Void,
        goBack: @escaping () -> Void,
        goForward: @escaping () -> Void,
        reload: @escaping () -> Void
    ) {
        guard let page = pages.first(where: { $0.id == pageID }) else { return }
        page.bindBridge(loadURL: loadURL, goBack: goBack, goForward: goForward, reload: reload)
    }

    func unbindBridge(for pageID: UUID) {
        guard let page = pages.first(where: { $0.id == pageID }) else { return }
        page.unbindBridge()
    }

    func submitAddress() {
        guard runtimeState == .ready, let activePage else { return }
        activePage.submitAddress(normalize: normalizedURLString(_:fallback:))
        syncActivePageState()
    }

    func setAddressBarEditing(_ isEditing: Bool) {
        activePage?.setAddressBarEditing(isEditing)
    }

    func updateAddressText(_ text: String) {
        activePage?.updateAddressText(text)
        addressText = text
    }

    func goBack() {
        guard runtimeState == .ready else { return }
        activePage?.goBack()
    }

    func goForward() {
        guard runtimeState == .ready else { return }
        activePage?.goForward()
    }

    func reload() {
        guard runtimeState == .ready else { return }
        activePage?.reload()
    }

    func openInDefaultBrowser() {
        let candidate = normalizedURLString(addressText, fallback: defaultPageURL.absoluteString)
        guard let url = URL(string: candidate) else { return }
        NSWorkspace.shared.open(url)
    }

    func openURLInNewTab(_ rawURL: String) {
        let normalized = normalizedURLString(rawURL, fallback: displayedURL)
        guard let url = URL(string: normalized) else { return }
        appendPage(initialURL: url, activate: true)
    }

    func updatePageState(
        for pageID: UUID,
        title: String?,
        url: String?,
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool
    ) {
        guard let page = pages.first(where: { $0.id == pageID }) else { return }
        page.updatePageState(
            title: title,
            url: url,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isLoading: isLoading)
    }

    func pageNavigationState(for pageID: UUID) -> (canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        guard let page = pages.first(where: { $0.id == pageID }) else {
            return (false, false, false)
        }
        return (page.canGoBack, page.canGoForward, page.isLoading)
    }

    func runtimeInstructions() -> [String] {
        BrowserPaths.installHintLines()
    }

    var installStatusText: String? {
        installPhase.statusText
    }

    var canInstallManagedRuntime: Bool {
        runtimeState != .ready &&
            runtimeState != .unsupportedBuild &&
            !installPhase.isWorking &&
            BrowserPaths.configuredCEFRuntimeOverride() == nil
    }

    var canRetryRuntimeActivation: Bool {
        runtimeState != .ready && !installPhase.isWorking
    }

    func installManagedRuntime() {
        guard canInstallManagedRuntime else { return }
        installTask?.cancel()
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await BrowserRuntimeInstaller.install { [weak self] phase in
                    self?.installPhase = phase
                }
                guard GhoDexCEFInitializeGlobal() else {
                    refreshRuntimeState()
                    installPhase = .failed(
                        AppLocalization.localizedText(
                            "Browser runtime installed, but Chromium could not be activated in this app session."))
                    installTask = nil
                    return
                }

                refreshRuntimeState()
                installPhase = .idle
                installTask = nil
            } catch {
                refreshRuntimeState()
                installPhase = .failed(error.localizedDescription)
                installTask = nil
            }
        }
    }

    func retryRuntimeActivation() {
        guard canRetryRuntimeActivation else { return }
        _ = GhoDexCEFInitializeGlobal()
        refreshRuntimeState()
    }

    func revealRuntimeFolder() {
        let runtimeRoot = BrowserPaths.configuredCEFRuntimeRoot()
        try? FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([runtimeRoot])
    }

    var restorableURL: URL {
        activePage?.restorableURL ?? defaultPageURL
    }

    func runtimeFailureMessage() -> String {
        switch runtimeState {
        case .ready:
            return ""
        case .unsupportedBuild:
            return AppLocalization.localizedText(
                "This build of GhoDex was compiled without managed Chromium runtime support."
            )
        case .runtimeUnavailable:
            if BrowserPaths.configuredCEFRuntimeOverride() != nil {
                return AppLocalization.localizedText(
                    "GhoDex could not find a compatible Chromium runtime at the configured custom runtime path."
                )
            }
            return AppLocalization.localizedText(
                "GhoDex needs to download its Chromium runtime before this browser tab can render pages."
            )
        case .initializationFailed:
            return AppLocalization.localizedText(
                "GhoDex found the Chromium runtime, but Chromium could not be activated in this app session."
            )
        }
    }

    private func appendPage(initialURL: URL, activate: Bool) {
        let page = BrowserPageState(initialURL: initialURL)
        register(page: page)
        pages.append(page)
        if activate {
            selectedPageID = page.id
            syncActivePageState()
        }
    }

    private func register(page: BrowserPageState) {
        page.onStateChange = { [weak self, weak page] in
            guard let self, let page else { return }
            if self.selectedPageID == page.id {
                self.syncActivePageState()
            }
        }
    }

    private func syncActivePageState() {
        let currentPage = activePage ?? pages.first
        pageTitle = currentPage?.pageTitle ?? AppLocalization.localizedText("Browser")
        displayedURL = currentPage?.displayedURL ?? defaultPageURL.absoluteString
        addressText = currentPage?.addressText ?? defaultPageURL.absoluteString
        canGoBack = currentPage?.canGoBack ?? false
        canGoForward = currentPage?.canGoForward ?? false
        isLoading = currentPage?.isLoading ?? false
    }

    private func normalizedURLString(_ rawValue: String, fallback: String?) -> String {
        BrowserPaths.normalizedURLString(rawValue, fallback: fallback ?? defaultPageURL.absoluteString)
    }

    private func refreshRuntimeState() {
        if !GhoDexCEFBuildSupportsManagedRuntime() {
            runtimeState = .unsupportedBuild
        } else if GhoDexCEFIsInitialized() {
            runtimeState = .ready
        } else if GhoDexCEFBuildHasRuntime() {
            runtimeState = .initializationFailed
        } else {
            runtimeState = .runtimeUnavailable
        }
    }
}
