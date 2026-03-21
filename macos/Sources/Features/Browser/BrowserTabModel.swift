import AppKit
import Foundation

enum BrowserControlCommandKind: String, Codable, Hashable {
    case loadURL
    case goBack
    case goForward
    case reload
    case executeJavaScript
    case evaluateJavaScript
    case listFrames
    case query
    case click
    case typeText
    case waitForSelector
    case getDOMSnapshot
    case getText
    case getAttributes
    case getBoundingBox
    case batchDOMCommands
}

enum BrowserControlEventKind: String, Codable, Hashable {
    case pageTitleChanged
    case navigationStateChanged
    case openURLInNewTabRequested
    case consoleMessage
    case bridgeReady
    case networkRequestFinished
}

enum BrowserControlErrorCode: String, Codable, Hashable {
    case pageNotFound
    case bridgeUnavailable
    case browserNotReady
    case invalidRequest
    case commandUnsupported
    case requestTimedOut
    case pageClosed
    case internalFailure
}

struct BrowserControlTarget: Hashable, Codable {
    let pageID: UUID
    let frameName: String?
    let documentRevision: Int

    init(pageID: UUID, frameName: String? = nil, documentRevision: Int) {
        self.pageID = pageID
        self.frameName = frameName
        self.documentRevision = documentRevision
    }
}

struct BrowserControlRequest: Identifiable, Hashable, Codable {
    let id: UUID
    let target: BrowserControlTarget
    let command: BrowserControlCommandKind
    let payload: [String: String]
    let timeoutMS: Int?

    init(
        id: UUID = UUID(),
        target: BrowserControlTarget,
        command: BrowserControlCommandKind,
        payload: [String: String] = [:],
        timeoutMS: Int? = nil
    ) {
        self.id = id
        self.target = target
        self.command = command
        self.payload = payload
        self.timeoutMS = timeoutMS
    }
}

struct BrowserControlError: Error, Hashable, Codable {
    let code: BrowserControlErrorCode
    let message: String
    let isRetryable: Bool

    static func bridgeUnavailable(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .bridgeUnavailable, message: message, isRetryable: true)
    }

    static func browserNotReady(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .browserNotReady, message: message, isRetryable: true)
    }

    static func invalidRequest(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .invalidRequest, message: message, isRetryable: false)
    }

    static func commandUnsupported(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .commandUnsupported, message: message, isRetryable: false)
    }

    static func pageNotFound(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .pageNotFound, message: message, isRetryable: false)
    }

    static func internalFailure(_ message: String) -> BrowserControlError {
        BrowserControlError(code: .internalFailure, message: message, isRetryable: false)
    }
}

struct BrowserControlResponse: Hashable, Codable {
    let requestID: UUID
    let target: BrowserControlTarget
    let stateRevision: Int
    let valueJSON: String?
    let error: BrowserControlError?

    static func success(for request: BrowserControlRequest, valueJSON: String? = nil) -> BrowserControlResponse {
        BrowserControlResponse(
            requestID: request.id,
            target: request.target,
            stateRevision: request.target.documentRevision,
            valueJSON: valueJSON,
            error: nil
        )
    }

    static func failure(for request: BrowserControlRequest, error: BrowserControlError) -> BrowserControlResponse {
        BrowserControlResponse(
            requestID: request.id,
            target: request.target,
            stateRevision: request.target.documentRevision,
            valueJSON: nil,
            error: error
        )
    }
}

struct BrowserDOMQueryResult: Hashable, Codable {
    let found: Bool
    let selector: String
    let tagName: String?
    let text: String
    let value: String?
    let html: String?
}

struct BrowserDOMClickResult: Hashable, Codable {
    let clicked: Bool
    let selector: String
}

struct BrowserDOMTypeTextResult: Hashable, Codable {
    let typed: Bool
    let selector: String
    let value: String
}

struct BrowserDOMTextResult: Hashable, Codable {
    let found: Bool
    let selector: String
    let text: String?
}

struct BrowserDOMAttributesResult: Hashable, Codable {
    let found: Bool
    let selector: String
    let attributes: [String: String]?
}

struct BrowserDOMBoundingBoxResult: Hashable, Codable {
    let found: Bool
    let selector: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let top: Double?
    let right: Double?
    let bottom: Double?
    let left: Double?
    let scrollX: Double?
    let scrollY: Double?
    let viewportWidth: Double?
    let viewportHeight: Double?
}

struct BrowserDOMSnapshotNode: Hashable, Codable {
    let tagName: String?
    let id: String?
    let className: String?
    let text: String?
    let attributes: [String: String]
    let childCount: Int
    let children: [BrowserDOMSnapshotNode]
}

struct BrowserDOMSnapshotResult: Hashable, Codable {
    let found: Bool
    let selector: String?
    let maxDepth: Int
    let includeText: Bool?
    let snapshot: BrowserDOMSnapshotNode?
}

enum BrowserDOMBatchCommandKind: String, Codable, Hashable {
    case query
    case click
    case typeText
    case getText
    case getAttributes
    case getBoundingBox
    case getDOMSnapshot
}

struct BrowserDOMBatchCommand: Identifiable, Hashable, Codable {
    let id: UUID
    let command: BrowserDOMBatchCommandKind
    let selector: String?
    let text: String?
    let maxDepth: Int?
    let includeText: Bool?

    init(
        id: UUID = UUID(),
        command: BrowserDOMBatchCommandKind,
        selector: String? = nil,
        text: String? = nil,
        maxDepth: Int? = nil,
        includeText: Bool? = nil
    ) {
        self.id = id
        self.command = command
        self.selector = selector
        self.text = text
        self.maxDepth = maxDepth
        self.includeText = includeText
    }
}

struct BrowserDOMBatchCommandResult: Hashable, Codable {
    let id: UUID
    let command: BrowserDOMBatchCommandKind
    let ok: Bool
    let valueJSON: String?
    let errorMessage: String?
}

struct BrowserDOMBatchResult: Hashable, Codable {
    let results: [BrowserDOMBatchCommandResult]
}

enum BrowserDOMBatchDecodedValue: Hashable {
    case query(BrowserDOMQueryResult)
    case click(BrowserDOMClickResult)
    case typeText(BrowserDOMTypeTextResult)
    case getText(BrowserDOMTextResult)
    case getAttributes(BrowserDOMAttributesResult)
    case getBoundingBox(BrowserDOMBoundingBoxResult)
    case getDOMSnapshot(BrowserDOMSnapshotResult)
}

struct BrowserDOMDecodedBatchCommandResult: Hashable {
    let id: UUID
    let command: BrowserDOMBatchCommandKind
    let value: BrowserDOMBatchDecodedValue?
    let error: BrowserControlError?
}

struct BrowserDOMDecodedBatchResult: Hashable {
    let results: [BrowserDOMDecodedBatchCommandResult]
}

extension BrowserDOMBatchResult {
    func decoded() -> BrowserDOMDecodedBatchResult {
        BrowserDOMDecodedBatchResult(results: results.map { $0.decoded() })
    }
}

extension BrowserDOMBatchCommandResult {
    func decoded() -> BrowserDOMDecodedBatchCommandResult {
        if !ok {
            return BrowserDOMDecodedBatchCommandResult(
                id: id,
                command: command,
                value: nil,
                error: .internalFailure(errorMessage ?? "The DOM batch command failed without an error message.")
            )
        }

        do {
            return BrowserDOMDecodedBatchCommandResult(
                id: id,
                command: command,
                value: try decodedValue(),
                error: nil
            )
        } catch let error as BrowserControlError {
            return BrowserDOMDecodedBatchCommandResult(
                id: id,
                command: command,
                value: nil,
                error: error
            )
        } catch {
            return BrowserDOMDecodedBatchCommandResult(
                id: id,
                command: command,
                value: nil,
                error: .internalFailure(error.localizedDescription)
            )
        }
    }

    private func decodedValue() throws -> BrowserDOMBatchDecodedValue {
        switch command {
        case .query:
            return .query(try decodeValueJSON(as: BrowserDOMQueryResult.self))
        case .click:
            return .click(try decodeValueJSON(as: BrowserDOMClickResult.self))
        case .typeText:
            return .typeText(try decodeValueJSON(as: BrowserDOMTypeTextResult.self))
        case .getText:
            return .getText(try decodeValueJSON(as: BrowserDOMTextResult.self))
        case .getAttributes:
            return .getAttributes(try decodeValueJSON(as: BrowserDOMAttributesResult.self))
        case .getBoundingBox:
            return .getBoundingBox(try decodeValueJSON(as: BrowserDOMBoundingBoxResult.self))
        case .getDOMSnapshot:
            return .getDOMSnapshot(try decodeValueJSON(as: BrowserDOMSnapshotResult.self))
        }
    }

    private func decodeValueJSON<T: Decodable>(as type: T.Type) throws -> T {
        guard let valueJSON, let data = valueJSON.data(using: .utf8) else {
            throw BrowserControlError.internalFailure("The DOM batch command returned no JSON payload.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BrowserControlError.internalFailure(
                "The DOM batch command returned an unexpected JSON payload: \(error.localizedDescription)"
            )
        }
    }
}

struct BrowserControlEvent: Identifiable, Hashable, Codable {
    let id: UUID
    let target: BrowserControlTarget
    let kind: BrowserControlEventKind
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        target: BrowserControlTarget,
        kind: BrowserControlEventKind,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.target = target
        self.kind = kind
        self.payload = payload
    }

    static func pageTitleChanged(target: BrowserControlTarget, title: String) -> BrowserControlEvent {
        BrowserControlEvent(target: target, kind: .pageTitleChanged, payload: ["title": title])
    }

    static func navigationStateChanged(
        target: BrowserControlTarget,
        url: String,
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool
    ) -> BrowserControlEvent {
        BrowserControlEvent(
            target: target,
            kind: .navigationStateChanged,
            payload: [
                "url": url,
                "canGoBack": String(canGoBack),
                "canGoForward": String(canGoForward),
                "isLoading": String(isLoading),
            ]
        )
    }

    static func openURLInNewTabRequested(target: BrowserControlTarget, url: String) -> BrowserControlEvent {
        BrowserControlEvent(target: target, kind: .openURLInNewTabRequested, payload: ["url": url])
    }

    static func consoleMessage(
        target: BrowserControlTarget,
        level: String,
        message: String,
        source: String,
        line: Int
    ) -> BrowserControlEvent {
        BrowserControlEvent(
            target: target,
            kind: .consoleMessage,
            payload: [
                "level": level,
                "message": message,
                "source": source,
                "line": String(line),
            ]
        )
    }

    static func bridgeReady(target: BrowserControlTarget, url: String) -> BrowserControlEvent {
        BrowserControlEvent(target: target, kind: .bridgeReady, payload: ["url": url])
    }

    // swiftlint:disable:next function_parameter_count
    static func networkRequestFinished(
        target: BrowserControlTarget,
        url: String,
        method: String,
        requestStatus: String,
        statusCode: Int,
        statusText: String,
        mimeType: String,
        receivedContentLength: Int64,
        isMainFrame: Bool,
        frameName: String
    ) -> BrowserControlEvent {
        BrowserControlEvent(
            target: target,
            kind: .networkRequestFinished,
            payload: [
                "url": url,
                "method": method,
                "requestStatus": requestStatus,
                "statusCode": String(statusCode),
                "statusText": statusText,
                "mimeType": mimeType,
                "receivedContentLength": String(receivedContentLength),
                "isMainFrame": String(isMainFrame),
                "frameName": frameName,
            ]
        )
    }
}

typealias BrowserControlCompletion = (BrowserControlResponse) -> Void
typealias BrowserControlEventObserver = (BrowserControlEvent) -> Void

struct BrowserPageControlBridge {
    let dispatch: (BrowserControlRequest, @escaping BrowserControlCompletion) -> Void
}

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
    @Published private(set) var documentRevision = 0

    fileprivate var onStateChange: (() -> Void)?
    fileprivate var isAddressBarEditing = false

    private var controlBridge: BrowserPageControlBridge?

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
        send(.loadURL, payload: ["url": normalized]) { _ in }
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
        send(.goBack) { _ in }
    }

    func goForward() {
        send(.goForward) { _ in }
    }

    func reload() {
        send(.reload) { _ in }
    }

    var controlTarget: BrowserControlTarget {
        BrowserControlTarget(pageID: id, documentRevision: documentRevision)
    }

    func bindControlBridge(_ bridge: BrowserPageControlBridge) {
        controlBridge = bridge
    }

    func unbindControlBridge() {
        controlBridge = nil
    }

    func route(_ request: BrowserControlRequest, completion: @escaping BrowserControlCompletion) {
        guard let controlBridge else {
            completion(.failure(for: request, error: .bridgeUnavailable("The browser page bridge is not bound.")))
            return
        }

        controlBridge.dispatch(request, completion)
    }

    func send(
        _ command: BrowserControlCommandKind,
        payload: [String: String] = [:],
        timeoutMS: Int? = nil,
        completion: @escaping BrowserControlCompletion
    ) {
        let request = BrowserControlRequest(
            target: controlTarget,
            command: command,
            payload: payload,
            timeoutMS: timeoutMS
        )
        route(request, completion: completion)
    }

    func query(
        selector: String,
        completion: @escaping (Result<BrowserDOMQueryResult, BrowserControlError>) -> Void
    ) {
        send(.query, payload: ["selector": selector]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMQueryResult.self))
        }
    }

    func click(
        selector: String,
        completion: @escaping (Result<BrowserDOMClickResult, BrowserControlError>) -> Void
    ) {
        send(.click, payload: ["selector": selector]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMClickResult.self))
        }
    }

    func typeText(
        selector: String,
        text: String,
        completion: @escaping (Result<BrowserDOMTypeTextResult, BrowserControlError>) -> Void
    ) {
        send(.typeText, payload: ["selector": selector, "text": text]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMTypeTextResult.self))
        }
    }

    func getText(
        selector: String,
        completion: @escaping (Result<BrowserDOMTextResult, BrowserControlError>) -> Void
    ) {
        send(.getText, payload: ["selector": selector]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMTextResult.self))
        }
    }

    func getAttributes(
        selector: String,
        completion: @escaping (Result<BrowserDOMAttributesResult, BrowserControlError>) -> Void
    ) {
        send(.getAttributes, payload: ["selector": selector]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMAttributesResult.self))
        }
    }

    func getBoundingBox(
        selector: String,
        completion: @escaping (Result<BrowserDOMBoundingBoxResult, BrowserControlError>) -> Void
    ) {
        send(.getBoundingBox, payload: ["selector": selector]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMBoundingBoxResult.self))
        }
    }

    func getDOMSnapshot(
        selector: String? = nil,
        maxDepth: Int = 2,
        includeText: Bool = true,
        completion: @escaping (Result<BrowserDOMSnapshotResult, BrowserControlError>) -> Void
    ) {
        var payload: [String: String] = [
            "maxDepth": String(max(0, maxDepth)),
            "includeText": String(includeText),
        ]
        if let selector, !selector.isEmpty {
            payload["selector"] = selector
        }

        send(.getDOMSnapshot, payload: payload) { response in
            completion(self.decodeResponse(response, as: BrowserDOMSnapshotResult.self))
        }
    }

    func runDOMCommandBatch(
        _ commands: [BrowserDOMBatchCommand],
        completion: @escaping (Result<BrowserDOMBatchResult, BrowserControlError>) -> Void
    ) {
        guard !commands.isEmpty else {
            completion(.failure(.invalidRequest("The browser DOM batch requires at least one command.")))
            return
        }

        let encoder = JSONEncoder()
        guard let encodedCommands = try? encoder.encode(commands),
              let commandsJSON = String(data: encodedCommands, encoding: .utf8)
        else {
            completion(.failure(.internalFailure("The browser DOM batch could not be encoded as JSON.")))
            return
        }

        send(.batchDOMCommands, payload: ["commandsJSON": commandsJSON]) { response in
            completion(self.decodeResponse(response, as: BrowserDOMBatchResult.self))
        }
    }

    func runDecodedDOMCommandBatch(
        _ commands: [BrowserDOMBatchCommand],
        completion: @escaping (Result<BrowserDOMDecodedBatchResult, BrowserControlError>) -> Void
    ) {
        runDOMCommandBatch(commands) { result in
            switch result {
            case let .success(batchResult):
                completion(.success(batchResult.decoded()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
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
            if displayedURL != url {
                documentRevision += 1
            }
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

    private func decodeResponse<T: Decodable>(
        _ response: BrowserControlResponse,
        as type: T.Type
    ) -> Result<T, BrowserControlError> {
        if let error = response.error {
            return .failure(error)
        }

        guard let valueJSON = response.valueJSON, let data = valueJSON.data(using: .utf8) else {
            return .failure(.internalFailure("The browser control command returned no JSON payload."))
        }

        do {
            let decodedValue = try JSONDecoder().decode(T.self, from: data)
            return .success(decodedValue)
        } catch {
            return .failure(.internalFailure("The browser control command returned an unexpected JSON payload: \(error.localizedDescription)"))
        }
    }
}

@MainActor
final class BrowserTabModel: ObservableObject {
    struct PageNavigationSnapshot {
        let url: String
        let canGoBack: Bool
        let canGoForward: Bool
        let isLoading: Bool
    }

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
    private var eventObservers: [UUID: EventObserverRegistration] = [:]

    init(initialURL: URL) {
        self.defaultPageURL = initialURL
        let initialPage = BrowserPageState(initialURL: initialURL)
        self.pages = [initialPage]
        self.selectedPageID = initialPage.id
        self.displayedURL = initialURL.absoluteString
        self.addressText = initialURL.absoluteString
        self.runtimeState = .runtimeUnavailable
        register(page: initialPage)

        // External callers can create Browser tabs very early in app startup.
        // If the model snapshots runtime state before global CEF init runs,
        // the view can get stuck on the disabled placeholder and never bind
        // the page bridge for that first tab.
        if GhoDexCEFBuildHasRuntime(), !GhoDexCEFIsInitialized() {
            _ = GhoDexCEFInitializeGlobal()
        }

        refreshRuntimeState()
        syncActivePageState()
    }

    deinit {
        installTask?.cancel()
    }

    @discardableResult
    func subscribeToControlEvents(
        pageID: UUID? = nil,
        kinds: Set<BrowserControlEventKind>? = nil,
        using observer: @escaping BrowserControlEventObserver
    ) -> UUID {
        let id = UUID()
        eventObservers[id] = EventObserverRegistration(pageID: pageID, kinds: kinds, observer: observer)
        return id
    }

    func unsubscribeFromControlEvents(_ id: UUID) {
        eventObservers.removeValue(forKey: id)
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
        bridge: BrowserPageControlBridge
    ) {
        guard let page = pages.first(where: { $0.id == pageID }) else { return }
        page.bindControlBridge(bridge)
    }

    func unbindBridge(for pageID: UUID) {
        guard let page = pages.first(where: { $0.id == pageID }) else { return }
        page.unbindControlBridge()
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

    func sendControlRequest(
        _ request: BrowserControlRequest,
        completion: @escaping BrowserControlCompletion
    ) {
        guard runtimeState == .ready else {
            completion(.failure(
                for: request,
                error: .browserNotReady("The browser runtime is not ready to handle control commands.")
            ))
            return
        }

        guard let page = pages.first(where: { $0.id == request.target.pageID }) else {
            completion(.failure(
                for: request,
                error: .pageNotFound("No browser page exists for \(request.target.pageID).")
            ))
            return
        }

        page.route(request, completion: completion)
    }

    func evaluateJavaScript(_ script: String, completion: @escaping BrowserControlCompletion) {
        guard let activePage else {
            let request = BrowserControlRequest(
                target: BrowserControlTarget(pageID: selectedPageID, documentRevision: 0),
                command: .evaluateJavaScript,
                payload: ["script": script]
            )
            completion(.failure(for: request, error: .pageNotFound("No active browser page is available.")))
            return
        }

        let request = BrowserControlRequest(
            target: activePage.controlTarget,
            command: .evaluateJavaScript,
            payload: ["script": script]
        )
        sendControlRequest(request, completion: completion)
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

    func controlTarget(for pageID: UUID) -> BrowserControlTarget? {
        pages.first(where: { $0.id == pageID })?.controlTarget
    }

    func requestInspectionSnapshot(
        for pageID: UUID,
        maxDepth: Int = 2,
        includeText: Bool = true,
        completion: @escaping (Result<BrowserDOMSnapshotResult, BrowserControlError>) -> Void
    ) {
        guard let page = pages.first(where: { $0.id == pageID }) else {
            completion(.failure(.pageNotFound("The browser page is no longer available.")))
            return
        }

        page.getDOMSnapshot(
            maxDepth: maxDepth,
            includeText: includeText,
            completion: completion
        )
    }

    func handle(_ event: BrowserControlEvent, from pageID: UUID) {
        switch event.kind {
        case .pageTitleChanged:
            updatePageState(
                for: pageID,
                title: event.payload["title"],
                url: nil,
                canGoBack: pageNavigationState(for: pageID).canGoBack,
                canGoForward: pageNavigationState(for: pageID).canGoForward,
                isLoading: pageNavigationState(for: pageID).isLoading
            )
        case .navigationStateChanged:
            updatePageState(
                for: pageID,
                title: nil,
                url: event.payload["url"],
                canGoBack: event.payload["canGoBack"] == "true",
                canGoForward: event.payload["canGoForward"] == "true",
                isLoading: event.payload["isLoading"] == "true"
            )
        case .openURLInNewTabRequested:
            if let url = event.payload["url"] {
                openURLInNewTab(url)
            }
        case .consoleMessage, .bridgeReady, .networkRequestFinished:
            break
        }

        emit(event)
    }

    func pageNavigationState(for pageID: UUID) -> PageNavigationSnapshot {
        guard let page = pages.first(where: { $0.id == pageID }) else {
            return PageNavigationSnapshot(url: "", canGoBack: false, canGoForward: false, isLoading: false)
        }
        return PageNavigationSnapshot(
            url: page.displayedURL,
            canGoBack: page.canGoBack,
            canGoForward: page.canGoForward,
            isLoading: page.isLoading
        )
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

    private func emit(_ event: BrowserControlEvent) {
        for registration in eventObservers.values {
            if let pageID = registration.pageID, pageID != event.target.pageID {
                continue
            }
            if let kinds = registration.kinds, !kinds.contains(event.kind) {
                continue
            }
            registration.observer(event)
        }
    }

    private struct EventObserverRegistration {
        let pageID: UUID?
        let kinds: Set<BrowserControlEventKind>?
        let observer: BrowserControlEventObserver
    }
}
