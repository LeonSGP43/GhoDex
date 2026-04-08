import AppKit
import Combine
import Foundation

/// AppleScript-facing wrapper around one top-level Browser context container.
///
/// The current implementation still uses `BrowserTabController` as the UI
/// container, so this wrapper preserves the legacy browser-tab scripting name
/// while routing both `browser.tab.v1` and `browser.context.v2` requests onto
/// the same controller-backed context object.
@MainActor
@objc(GhosttyScriptBrowserTab)
final class ScriptBrowserTab: NSObject {
    private static let externalCommandStartupTimeout: TimeInterval = 120.0
    private static let externalCommandTimeoutBuffer: TimeInterval = 5.0

    let stableID: String

    private weak var controller: BrowserTabController?

    init(controller: BrowserTabController) {
        self.stableID = Self.stableID(controller: controller)
        self.controller = controller
    }

    @objc(id)
    var idValue: String {
        guard NSApp.isAppleScriptEnabled else { return "" }
        return stableID
    }

    @objc(title)
    var title: String {
        guard NSApp.isAppleScriptEnabled else { return "" }
        return controller?.model.pageTitle ?? ""
    }

    @objc(url)
    var url: String {
        guard NSApp.isAppleScriptEnabled else { return "" }
        return controller?.model.displayedURL ?? ""
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard NSApp.isAppleScriptEnabled else { return nil }
        guard let appClassDescription = NSApplication.shared.classDescription as? NSScriptClassDescription else {
            return nil
        }

        return NSUniqueIDSpecifier(
            containerClassDescription: appClassDescription,
            containerSpecifier: nil,
            key: "browserTabs",
            uniqueID: stableID
        )
    }

    fileprivate func load(url rawURL: String, pageID: UUID? = nil) -> Result<Bool, BrowserControlError> {
        let timeout = Self.externalCommandTimeout()

        switch waitForPageBridgeSynchronously(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return awaitControlResultSynchronously(timeout: timeout) { completion in
            issueLoad(url: rawURL, pageID: pageID, completion: completion)
        }
    }

    fileprivate func loadAsync(url rawURL: String, pageID: UUID? = nil) async -> Result<Bool, BrowserControlError> {
        let timeout = Self.externalCommandTimeout()

        switch await waitForPageBridge(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return await awaitControlResult(timeout: timeout) { completion in
            issueLoad(url: rawURL, pageID: pageID, completion: completion)
        }
    }

    fileprivate func evaluate(
        javaScript script: String,
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        let timeout = Self.externalCommandTimeout()

        switch waitForPageBridgeSynchronously(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return awaitControlResultSynchronously(timeout: timeout) { completion in
            issueEvaluation(javaScript: script, pageID: pageID, frameName: frameName, completion: completion)
        }
    }

    fileprivate func evaluateAsync(
        javaScript script: String,
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        let timeout = Self.externalCommandTimeout()

        switch await waitForPageBridge(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return await awaitControlResult(timeout: timeout) { completion in
            issueEvaluation(javaScript: script, pageID: pageID, frameName: frameName, completion: completion)
        }
    }

    fileprivate func getCookies(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        switch Self.cookieInspectionScript(payload: payload) {
        case let .success(script):
            return evaluate(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func getCookiesAsync(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        switch Self.cookieInspectionScript(payload: payload) {
        case let .success(script):
            return await evaluateAsync(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func setCookie(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .set, payload: payload) {
        case let .success(script):
            return evaluate(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func setCookieAsync(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .set, payload: payload) {
        case let .success(script):
            return await evaluateAsync(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func deleteCookie(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .delete, payload: payload) {
        case let .success(script):
            return evaluate(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func deleteCookieAsync(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .delete, payload: payload) {
        case let .success(script):
            return await evaluateAsync(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func clearCookies(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .clear, payload: payload) {
        case let .success(script):
            return evaluate(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func clearCookiesAsync(
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        switch Self.cookieMutationScript(operation: .clear, payload: payload) {
        case let .success(script):
            return await evaluateAsync(javaScript: script, pageID: pageID, frameName: frameName)
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func runDOMBatch(
        commandsJSON: String,
        pageID: UUID? = nil,
        frameName: String? = nil
    ) -> Result<String, BrowserControlError> {
        switch decodeDOMBatchCommands(commandsJSON: commandsJSON) {
        case let .success(commands):
            let timeout = Self.externalCommandTimeout()

            switch waitForPageBridgeSynchronously(pageID: pageID, timeout: timeout) {
            case .success:
                break
            case let .failure(error):
                return .failure(error)
            }

            return awaitControlResultSynchronously(timeout: timeout) { completion in
                issueDOMBatch(commands: commands, pageID: pageID, frameName: frameName, completion: completion)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func runDOMBatchAsync(
        commandsJSON: String,
        pageID: UUID? = nil,
        frameName: String? = nil
    ) async -> Result<String, BrowserControlError> {
        switch decodeDOMBatchCommands(commandsJSON: commandsJSON) {
        case let .success(commands):
            let timeout = Self.externalCommandTimeout()

            switch await waitForPageBridge(pageID: pageID, timeout: timeout) {
            case .success:
                break
            case let .failure(error):
                return .failure(error)
            }

            return await awaitControlResult(timeout: timeout) { completion in
                issueDOMBatch(commands: commands, pageID: pageID, frameName: frameName, completion: completion)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    fileprivate func listFrames(pageID: UUID? = nil) -> Result<String, BrowserControlError> {
        let timeout = Self.externalCommandTimeout()

        switch waitForPageBridgeSynchronously(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return awaitControlResultSynchronously(timeout: timeout) { completion in
            issueListFrames(pageID: pageID, completion: completion)
        }
    }

    fileprivate func runExternalDOMCommand(
        _ command: BrowserControlCommandKind,
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil,
        timeoutMS: Int? = nil
    ) -> Result<String, BrowserControlError> {
        let timeout = Self.externalCommandTimeout(timeoutMS: timeoutMS)

        switch waitForPageBridgeSynchronously(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return awaitControlResultSynchronously(timeout: timeout) { completion in
            issueExternalDOMCommand(
                command,
                payload: payload,
                pageID: pageID,
                frameName: frameName,
                timeoutMS: timeoutMS,
                completion: completion
            )
        }
    }

    fileprivate func runExternalDOMCommandAsync(
        _ command: BrowserControlCommandKind,
        payload: [String: String],
        pageID: UUID? = nil,
        frameName: String? = nil,
        timeoutMS: Int? = nil
    ) async -> Result<String, BrowserControlError> {
        let timeout = Self.externalCommandTimeout(timeoutMS: timeoutMS)

        switch await waitForPageBridge(pageID: pageID, timeout: timeout) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        return await awaitControlResult(timeout: timeout) { completion in
            issueExternalDOMCommand(
                command,
                payload: payload,
                pageID: pageID,
                frameName: frameName,
                timeoutMS: timeoutMS,
                completion: completion
            )
        }
    }

    private func decodeDOMBatchCommands(commandsJSON: String) -> Result<[BrowserDOMBatchCommand], BrowserControlError> {
        do {
            guard let data = commandsJSON.data(using: .utf8) else {
                return .failure(.invalidRequest("The DOM batch JSON must be valid UTF-8 text."))
            }
            return .success(try JSONDecoder().decode([BrowserDOMBatchCommand].self, from: data))
        } catch {
            return .failure(.invalidRequest("The DOM batch JSON must decode to an array of browser DOM batch commands."))
        }
    }

    private func issueLoad(
        url rawURL: String,
        pageID: UUID?,
        completion: @escaping (Result<Bool, BrowserControlError>) -> Void
    ) {
        guard let page = requestedPage(pageID) else {
            completion(.failure(.pageNotFound(pageNotFoundMessage(for: pageID))))
            return
        }

        let normalizedURL = BrowserPaths.normalizedURLString(rawURL, fallback: page.displayedURL)
        page.send(.loadURL, payload: ["url": normalizedURL]) { response in
            if let error = response.error {
                completion(.failure(error))
                return
            }

            completion(.success(true))
        }
    }

    private func issueEvaluation(
        javaScript script: String,
        pageID: UUID?,
        frameName: String?,
        completion: @escaping (Result<String, BrowserControlError>) -> Void
    ) {
        guard let page = requestedPage(pageID) else {
            completion(.failure(.pageNotFound(pageNotFoundMessage(for: pageID))))
            return
        }

        let request = BrowserControlRequest(
            target: BrowserControlTarget(pageID: page.id, frameName: frameName, documentRevision: page.documentRevision),
            command: .evaluateJavaScript,
            payload: ["script": script]
        )
        page.route(request) { response in
            if let error = response.error {
                completion(.failure(error))
                return
            }

            completion(.success(response.valueJSON ?? "null"))
        }
    }

    private func issueDOMBatch(
        commands: [BrowserDOMBatchCommand],
        pageID: UUID?,
        frameName: String?,
        completion: @escaping (Result<String, BrowserControlError>) -> Void
    ) {
        guard let page = requestedPage(pageID) else {
            completion(.failure(.pageNotFound(pageNotFoundMessage(for: pageID))))
            return
        }

        let commandsJSON: String
        do {
            commandsJSON = try Self.encodedDOMBatchCommands(commands)
        } catch let error as BrowserControlError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.internalFailure("The browser DOM batch could not be encoded as JSON.")))
            return
        }

        let request = BrowserControlRequest(
            target: BrowserControlTarget(pageID: page.id, frameName: frameName, documentRevision: page.documentRevision),
            command: .batchDOMCommands,
            payload: ["commandsJSON": commandsJSON]
        )
        page.route(request) { response in
            let result = Self.decodeDOMBatchResponse(response)
            switch result {
            case let .success(decodedResult):
                do {
                    completion(.success(try Self.jsonString(from: decodedResult)))
                } catch {
                    completion(.failure(.internalFailure("The decoded DOM batch result could not be encoded as JSON.")))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func issueListFrames(
        pageID: UUID?,
        completion: @escaping (Result<String, BrowserControlError>) -> Void
    ) {
        guard let page = requestedPage(pageID) else {
            completion(.failure(.pageNotFound(pageNotFoundMessage(for: pageID))))
            return
        }

        let request = BrowserControlRequest(
            target: BrowserControlTarget(pageID: page.id, documentRevision: page.documentRevision),
            command: .listFrames
        )
        page.route(request) { response in
            if let error = response.error {
                completion(.failure(error))
                return
            }

            completion(.success(response.valueJSON ?? "[]"))
        }
    }

    private func issueExternalDOMCommand(
        _ command: BrowserControlCommandKind,
        payload: [String: String],
        pageID: UUID?,
        frameName: String?,
        timeoutMS: Int?,
        completion: @escaping (Result<String, BrowserControlError>) -> Void
    ) {
        guard let page = requestedPage(pageID) else {
            completion(.failure(.pageNotFound(pageNotFoundMessage(for: pageID))))
            return
        }

        let request = BrowserControlRequest(
            target: BrowserControlTarget(pageID: page.id, frameName: frameName, documentRevision: page.documentRevision),
            command: command,
            payload: payload,
            timeoutMS: timeoutMS
        )
        page.route(request) { response in
            if let error = response.error {
                completion(.failure(error))
                return
            }

            completion(.success(response.valueJSON ?? "null"))
        }
    }

    private static func encodedDOMBatchCommands(_ commands: [BrowserDOMBatchCommand]) throws -> String {
        let encoder = JSONEncoder()
        let encodedCommands = try encoder.encode(commands)
        guard let commandsJSON = String(data: encodedCommands, encoding: .utf8) else {
            throw BrowserControlError.internalFailure("The browser DOM batch could not be encoded as UTF-8.")
        }
        return commandsJSON
    }

    private static func decodeDOMBatchResponse(
        _ response: BrowserControlResponse
    ) -> Result<BrowserDOMDecodedBatchResult, BrowserControlError> {
        if let error = response.error {
            return .failure(error)
        }

        guard let valueJSON = response.valueJSON, let data = valueJSON.data(using: .utf8) else {
            return .failure(.internalFailure("The browser control command returned no JSON payload."))
        }

        do {
            let decodedValue = try JSONDecoder().decode(BrowserDOMBatchResult.self, from: data)
            return .success(decodedValue.decoded())
        } catch {
            return .failure(.internalFailure("The browser control command returned an unexpected JSON payload: \(error.localizedDescription)"))
        }
    }

    private static func externalCommandTimeout(timeoutMS: Int? = nil) -> TimeInterval {
        let commandTimeout = timeoutMS.map { TimeInterval(max(0, $0)) / 1000.0 + externalCommandTimeoutBuffer } ?? 0
        return max(externalCommandStartupTimeout, commandTimeout)
    }

    private func awaitControlResult<T>(
        timeout: TimeInterval = 5.0,
        _ operation: (@escaping (Result<T, BrowserControlError>) -> Void) -> Void
    ) async -> Result<T, BrowserControlError> {
        let gate = BrowserControlAwaitGate()
        let timeoutError = BrowserControlError(
            code: .requestTimedOut,
            message: "Timed out while waiting for the browser scripting command to finish.",
            isRetryable: true
        )
        var timeoutTask: Task<Void, Never>?

        return await withCheckedContinuation { continuation in
            func finish(_ result: Result<T, BrowserControlError>) {
                guard gate.tryFinish() else { return }
                timeoutTask?.cancel()
                continuation.resume(returning: result)
            }

            operation { result in
                finish(result)
            }

            timeoutTask = Task { @MainActor in
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if Task.isCancelled { return }
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                    await Task.yield()
                }

                finish(.failure(timeoutError))
            }
        }
    }

    private func awaitControlResultSynchronously<T>(
        timeout: TimeInterval = 5.0,
        _ operation: (@escaping (Result<T, BrowserControlError>) -> Void) -> Void
    ) -> Result<T, BrowserControlError> {
        var finalResult: Result<T, BrowserControlError>?
        operation { result in
            finalResult = result
        }

        let deadline = Date().addingTimeInterval(timeout)
        while finalResult == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        return finalResult ?? .failure(
            BrowserControlError(
                code: .requestTimedOut,
                message: "Timed out while waiting for the browser scripting command to finish.",
                isRetryable: true
            )
        )
    }

    private func waitForPageBridge(
        pageID: UUID?,
        timeout: TimeInterval = 15.0
    ) async -> Result<Void, BrowserControlError> {
        guard let page = requestedPage(pageID) else {
            return .failure(.pageNotFound(pageNotFoundMessage(for: pageID)))
        }

        if page.isControlBridgeReady {
            return .success(())
        }

        prepareForExternalControlStartup()

        let gate = BrowserControlAwaitGate()
        var readinessCancellable: AnyCancellable?
        var monitorTask: Task<Void, Never>?

        return await withCheckedContinuation { continuation in
            func finish(_ result: Result<Void, BrowserControlError>) {
                guard gate.tryFinish() else { return }
                readinessCancellable?.cancel()
                monitorTask?.cancel()
                continuation.resume(returning: result)
            }

            readinessCancellable = page.controlBridgeReadyPublisher()
                .removeDuplicates()
                .filter { $0 }
                .sink { _ in
                    finish(.success(()))
                }

            monitorTask = Task { @MainActor in
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if Task.isCancelled { return }
                    if page.isControlBridgeReady {
                        finish(.success(()))
                        return
                    }
                    if let initializationError = GhoDexCEFLastInitializationError(), !initializationError.isEmpty {
                        finish(.failure(.bridgeUnavailable(initializationError)))
                        return
                    }
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                    await Task.yield()
                }

                finish(.failure(.bridgeUnavailable("The browser page bridge did not become ready in time.")))
            }
        }
    }

    private func waitForPageBridgeSynchronously(
        pageID: UUID?,
        timeout: TimeInterval = 15.0
    ) -> Result<Void, BrowserControlError> {
        guard let page = requestedPage(pageID) else {
            return .failure(.pageNotFound(pageNotFoundMessage(for: pageID)))
        }

        if page.isControlBridgeReady {
            return .success(())
        }

        prepareForExternalControlStartup()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if page.isControlBridgeReady {
                return .success(())
            }
            if let initializationError = GhoDexCEFLastInitializationError(), !initializationError.isEmpty {
                return .failure(.bridgeUnavailable(initializationError))
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        return .failure(.bridgeUnavailable("The browser page bridge did not become ready in time."))
    }

    private static func jsonString(from decodedResult: BrowserDOMDecodedBatchResult) throws -> String {
        let payload = [
            "results": decodedResult.results.map(jsonObject(for:)),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw BrowserControlError.internalFailure("The decoded DOM batch result could not be serialized as UTF-8.")
        }
        return encoded
    }

    private static func jsonObject(for result: BrowserDOMDecodedBatchCommandResult) -> [String: Any] {
        [
            "id": result.id.uuidString,
            "command": result.command.rawValue,
            "ok": result.error == nil,
            "value": result.value.flatMap { try? jsonObject(for: $0) } ?? NSNull(),
            "error": result.error.flatMap { try? jsonObject(from: $0) } ?? NSNull(),
        ]
    }

    private static func jsonObject(for value: BrowserDOMBatchDecodedValue) throws -> Any {
        switch value {
        case let .query(result):
            return try jsonObject(from: result)
        case let .click(result):
            return try jsonObject(from: result)
        case let .typeText(result):
            return try jsonObject(from: result)
        case let .getText(result):
            return try jsonObject(from: result)
        case let .getAttributes(result):
            return try jsonObject(from: result)
        case let .getBoundingBox(result):
            return try jsonObject(from: result)
        case let .getDOMSnapshot(result):
            return try jsonObject(from: result)
        }
    }

    private static func jsonObject<T: Encodable>(from value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func requestedPage(_ pageID: UUID?) -> BrowserPageState? {
        guard let controller else { return nil }
        guard let pageID else { return controller.model.activePage }
        return controller.model.pages.first(where: { $0.id == pageID })
    }

    private func pageNotFoundMessage(for pageID: UUID?) -> String {
        if let pageID {
            return "No browser page exists for \(pageID.uuidString)."
        }
        return "No active browser page is available."
    }

    private func waitForActivePageBridge(timeout: TimeInterval = 15.0) async -> Result<Void, BrowserControlError> {
        await waitForPageBridge(pageID: controller?.model.activePage?.id, timeout: timeout)
    }

    private func waitForActivePageBridgeSynchronously(timeout: TimeInterval = 15.0) -> Result<Void, BrowserControlError> {
        waitForPageBridgeSynchronously(pageID: controller?.model.activePage?.id, timeout: timeout)
    }

    private func prepareForExternalControlStartup() {
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller?.model.ensureRuntimeActivationForExternalControl()
    }
}

private final class BrowserControlAwaitGate {
    private let lock = NSLock()
    private var finished = false

    func tryFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

extension ScriptBrowserTab {
    private struct ResolvedExternalPageTarget {
        let browserTab: ScriptBrowserTab
        let pageID: UUID?
        let frameName: String?
        let page: BrowserPageState
    }

    static func stableID(controller: BrowserTabController) -> String {
        controller.externalID
    }

    var tabSummary: BrowserExternalTabSummary {
        BrowserExternalTabSummary(
            id: stableID,
            title: controller?.model.pageTitle ?? "",
            url: controller?.model.displayedURL ?? ""
        )
    }

    var contextSummary: BrowserExternalContextSummary {
        let controller = controller
        return BrowserExternalContextSummary(
            id: stableID,
            title: controller?.model.pageTitle ?? "",
            url: controller?.model.displayedURL ?? "",
            activePageID: controller?.model.selectedPageID.uuidString,
            pageCount: controller?.model.pages.count ?? 0,
            isFrontmost: BrowserTabController.frontmostControllerID == stableID,
            contextPolicy: controller?.contextPolicy ?? .default
        )
    }

    var pageSummaries: [BrowserExternalPageSummary] {
        guard let controller else { return [] }
        return controller.model.pages.map { page in
            BrowserExternalPageSummary(
                id: page.id.uuidString,
                title: page.pageTitle,
                url: page.displayedURL,
                isActive: page.id == controller.model.selectedPageID,
                documentRevision: page.documentRevision
            )
        }
    }

    var activePageSummary: BrowserExternalPageSummary? {
        pageSummaries.first(where: \.isActive)
    }

    func activateContext() -> Result<BrowserExternalContextSummary, BrowserControlError> {
        guard let controller else {
            return .failure(.pageNotFound("No Browser context is available for activation."))
        }

        controller.activateContext()
        return .success(contextSummary)
    }

    func newPage(initialURL rawURL: String?) -> Result<BrowserExternalPageSummary, BrowserControlError> {
        guard let controller else {
            return .failure(.pageNotFound("No Browser context is available for page creation."))
        }

        let page: BrowserPageState?
        if let rawURL, !rawURL.isEmpty {
            page = controller.model.openURLInNewTab(rawURL, activate: true)
        } else {
            controller.model.newPageTab()
            page = controller.model.activePage
        }

        guard let page else {
            return .failure(.internalFailure("The Browser context could not create a new page."))
        }

        guard let summary = controller.model.pages.first(where: { $0.id == page.id }).map({ page in
            BrowserExternalPageSummary(
                id: page.id.uuidString,
                title: page.pageTitle,
                url: page.displayedURL,
                isActive: page.id == controller.model.selectedPageID,
                documentRevision: page.documentRevision
            )
        }) else {
            return .failure(.internalFailure("The new Browser page summary could not be resolved."))
        }

        return .success(summary)
    }

    func activatePage(pageID rawPageID: String) -> Result<BrowserExternalPageSummary, BrowserControlError> {
        guard let controller else {
            return .failure(.pageNotFound("No Browser context is available for page activation."))
        }

        guard let pageID = UUID(uuidString: rawPageID) else {
            return .failure(.invalidRequest("The pageID payload must be a UUID string."))
        }

        guard controller.model.pages.contains(where: { $0.id == pageID }) else {
            return .failure(.pageNotFound("No browser page exists for \(rawPageID)."))
        }

        controller.model.selectPage(pageID)
        guard let summary = activePageSummary else {
            return .failure(.internalFailure("The Browser tab active page could not be resolved after activation."))
        }

        return .success(summary)
    }

    func closePage(pageID rawPageID: String?) -> Result<BrowserExternalPageCloseResult, BrowserControlError> {
        guard let controller else {
            return .failure(.pageNotFound("No Browser context is available for page closure."))
        }

        let targetPageID: UUID
        if let rawPageID, !rawPageID.isEmpty {
            guard let parsed = UUID(uuidString: rawPageID) else {
                return .failure(.invalidRequest("The pageID payload must be a UUID string."))
            }
            targetPageID = parsed
        } else if let activePageID = controller.model.activePage?.id {
            targetPageID = activePageID
        } else {
            return .failure(.internalFailure("No active browser page is available for closure."))
        }

        guard controller.model.pages.contains(where: { $0.id == targetPageID }) else {
            return .failure(.pageNotFound("No browser page exists for \(targetPageID.uuidString)."))
        }

        guard controller.model.pages.count > 1 else {
            return .failure(.invalidRequest("closePage requires at least two pages in the Browser context; use closeContext to close the last page."))
        }

        controller.model.closePage(targetPageID)

        return .success(
            BrowserExternalPageCloseResult(
                closedPageID: targetPageID.uuidString,
                remainingPageCount: controller.model.pages.count,
                activePageID: controller.model.activePage?.id.uuidString
            )
        )
    }

    func closeContext() -> Result<BrowserExternalContextCloseResult, BrowserControlError> {
        guard let controller else {
            return .failure(.pageNotFound("No Browser context is available for closure."))
        }

        let closedContextID = stableID
        let closedPageCount = controller.model.pages.count
        controller.closeContextImmediately()
        return .success(
            BrowserExternalContextCloseResult(
                closedContextID: closedContextID,
                closedPageCount: closedPageCount
            )
        )
    }

    static func parseRequestedPageID(from request: BrowserExternalCommandRequest) -> Result<UUID?, BrowserExternalCommandError> {
        guard let rawPageID = request.pageID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPageID.isEmpty else {
            return .success(nil)
        }

        guard let pageID = UUID(uuidString: rawPageID) else {
            return .failure(.invalidRequest("The pageID field must be a UUID string when provided."))
        }

        return .success(pageID)
    }

    static func parseRequestedFrameName(from request: BrowserExternalCommandRequest) -> String? {
        guard let rawFrameName = request.frameName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawFrameName.isEmpty else {
            return nil
        }
        return rawFrameName
    }

    private static func parseTimeoutMS(from payload: [String: String]) -> Result<Int?, BrowserExternalCommandError> {
        guard let rawTimeout = payload["timeoutMS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTimeout.isEmpty else {
            return .success(nil)
        }

        guard let timeoutMS = Int(rawTimeout), timeoutMS >= 0 else {
            return .failure(.invalidRequest("The timeoutMS payload must be a non-negative integer string when provided."))
        }

        return .success(timeoutMS)
    }

    private static func routeExternalDOMCommandAsync(
        _ request: BrowserExternalCommandRequest,
        command: BrowserControlCommandKind
    ) async -> BrowserExternalCommandResponse {
        let target: ResolvedExternalPageTarget
        switch resolvePageTarget(for: request) {
        case let .success(resolved):
            target = resolved
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        let timeoutMS: Int?
        switch parseTimeoutMS(from: request.payload) {
        case let .success(parsed):
            timeoutMS = parsed
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        switch await target.browserTab.runExternalDOMCommandAsync(
            command,
            payload: request.payload,
            pageID: target.page.id,
            frameName: target.frameName,
            timeoutMS: timeoutMS
        ) {
        case let .success(resultJSON):
            return .success(for: request, resultJSON: resultJSON)
        case let .failure(error):
            return .failure(for: request, error: error.externalCommandError)
        }
    }

    private static func routeExternalDOMCommand(
        _ request: BrowserExternalCommandRequest,
        command: BrowserControlCommandKind
    ) -> BrowserExternalCommandResponse {
        let target: ResolvedExternalPageTarget
        switch resolvePageTarget(for: request) {
        case let .success(resolved):
            target = resolved
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        let timeoutMS: Int?
        switch parseTimeoutMS(from: request.payload) {
        case let .success(parsed):
            timeoutMS = parsed
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        switch target.browserTab.runExternalDOMCommand(
            command,
            payload: request.payload,
            pageID: target.page.id,
            frameName: target.frameName,
            timeoutMS: timeoutMS
        ) {
        case let .success(resultJSON):
            return .success(for: request, resultJSON: resultJSON)
        case let .failure(error):
            return .failure(for: request, error: error.externalCommandError)
        }
    }

    private static func routeExternalRuntimePromptResolutionCommand(
        _ request: BrowserExternalCommandRequest,
        command: BrowserControlCommandKind
    ) -> BrowserExternalCommandResponse {
        let target: ResolvedExternalPageTarget
        switch resolvePageTarget(for: request) {
        case let .success(resolved):
            target = resolved
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        let resolutionRequest: BrowserRuntimePromptResolutionRequest
        do {
            resolutionRequest = try BrowserRuntimePromptResolutionRequest.from(
                command: request.command,
                payload: request.payload
            )
        } catch let error as BrowserExternalCommandError {
            return .failure(for: request, error: error)
        } catch {
            return .failure(for: request, error: .invalidRequest("The runtime prompt resolution payload is invalid."))
        }

        switch target.browserTab.runExternalDOMCommand(
            command,
            payload: resolutionRequest.controlPayload,
            pageID: target.page.id,
            frameName: target.frameName,
            timeoutMS: nil
        ) {
        case .success:
            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(
                        from: BrowserExternalRuntimeResolutionAck(
                            requestID: resolutionRequest.requestID,
                            kind: resolutionRequest.kind,
                            resolved: true
                        )
                    )
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The runtime prompt resolution acknowledgment could not be serialized as JSON.")
                )
            }
        case let .failure(error):
            return .failure(for: request, error: error.externalCommandError)
        }
    }

    private static func routeExternalDownloadControlCommand(
        _ request: BrowserExternalCommandRequest,
        command: BrowserControlCommandKind
    ) -> BrowserExternalCommandResponse {
        let target: ResolvedExternalPageTarget
        switch resolvePageTarget(for: request) {
        case let .success(resolved):
            target = resolved
        case let .failure(error):
            return .failure(for: request, error: error)
        }

        let controlRequest: BrowserDownloadControlRequest
        do {
            switch request.command {
            case .cancelDownload:
                controlRequest = try BrowserDownloadControlRequest.cancel(from: request.payload)
            default:
                return .failure(
                    for: request,
                    error: .invalidRequest("The \(request.command.rawValue) command is not a download control command.")
                )
            }
        } catch let error as BrowserExternalCommandError {
            return .failure(for: request, error: error)
        } catch {
            return .failure(for: request, error: .invalidRequest("The download control payload is invalid."))
        }

        switch target.browserTab.runExternalDOMCommand(
            command,
            payload: controlRequest.controlPayload,
            pageID: target.page.id,
            frameName: target.frameName,
            timeoutMS: nil
        ) {
        case .success:
            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(
                        from: BrowserExternalDownloadControlAck(
                            downloadID: controlRequest.downloadID,
                            accepted: true,
                            operation: controlRequest.operation
                        )
                    )
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The download control acknowledgment could not be serialized as JSON.")
                )
            }
        case let .failure(error):
            return .failure(for: request, error: error.externalCommandError)
        }
    }

    private static func resolvePageTarget(
        for request: BrowserExternalCommandRequest
    ) -> Result<ResolvedExternalPageTarget, BrowserExternalCommandError> {
        guard let browserTab = browserTab(for: request) else {
            return .failure(.invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
        }

        let requestedPageID: UUID?
        switch parseRequestedPageID(from: request) {
        case let .success(pageID):
            requestedPageID = pageID
        case let .failure(error):
            return .failure(error)
        }

        guard let page = browserTab.requestedPage(requestedPageID) else {
            if let requestedPageID {
                return .failure(.invalidRequest("The pageID does not resolve to a live browser page in this Browser context."))
            }
            return .failure(.internalFailure("No active browser page is available."))
        }

        if let expectedRevision = request.documentRevision, page.documentRevision != expectedRevision {
            return .failure(
                .staleDocumentRevision(
                    "The requested browser page no longer matches documentRevision \(expectedRevision). Current revision is \(page.documentRevision)."
                )
            )
        }

        return .success(
            ResolvedExternalPageTarget(
                browserTab: browserTab,
                pageID: requestedPageID,
                frameName: parseRequestedFrameName(from: request),
                page: page
            )
        )
    }

    static func runExternalCommandProtocol(requestJSON: String) async throws -> String {
        let request = try decodeExternalCommandRequest(requestJSON)
        let response = await routeExternalCommandAsync(request)
        return try response.jsonString()
    }

    static func runExternalCommandProtocolSynchronously(requestJSON: String) throws -> String {
        let request = try decodeExternalCommandRequest(requestJSON)
        let response = routeExternalCommand(request)
        return try response.jsonString()
    }

    private static func decodeExternalCommandRequest(_ requestJSON: String) throws -> BrowserExternalCommandRequest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let requestData = requestJSON.data(using: .utf8) else {
            throw BrowserExternalCommandError.invalidRequest("The browser command protocol request must be valid UTF-8 JSON.")
        }

        do {
            return try decoder.decode(BrowserExternalCommandRequest.self, from: requestData)
        } catch {
            throw BrowserExternalCommandError.invalidRequest("The browser command protocol request could not be decoded.")
        }
    }

    static func routeExternalCommandAsync(_ request: BrowserExternalCommandRequest) async -> BrowserExternalCommandResponse {
        if let versionError = request.validateVersion() {
            return .failure(for: request, error: versionError)
        }

        switch request.command {
        case .listPages, .getActivePage, .activatePage, .listFrames:
            return routeExternalCommand(request)
        case .newPageInContext:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            switch browserTab.newPage(initialURL: request.payload["url"]) {
            case let .success(summary):
                browserTab.prepareForExternalControlStartup()
                do {
                    return .success(for: request, resultJSON: try jsonString(from: summary))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The new Browser page summary could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .query:
            return await routeExternalDOMCommandAsync(request, command: .query)
        case .click:
            return await routeExternalDOMCommandAsync(request, command: .click)
        case .typeText:
            return await routeExternalDOMCommandAsync(request, command: .typeText)
        case .waitForSelector:
            return await routeExternalDOMCommandAsync(request, command: .waitForSelector)
        case .getText:
            return await routeExternalDOMCommandAsync(request, command: .getText)
        case .getAttributes:
            return await routeExternalDOMCommandAsync(request, command: .getAttributes)
        case .getBoundingBox:
            return await routeExternalDOMCommandAsync(request, command: .getBoundingBox)
        case .getDOMSnapshot:
            return await routeExternalDOMCommandAsync(request, command: .getDOMSnapshot)
        case .newTab:
            guard let appDelegate = NSApp.delegate as? AppDelegate else {
                return .failure(for: request, error: .internalFailure("The GhoDex app delegate is unavailable."))
            }

            let initialURL: URL?
            if let rawURL = request.payload["url"], !rawURL.isEmpty {
                let normalizedURL = BrowserPaths.normalizedURLString(
                    rawURL,
                    fallback: BrowserTabController.defaultHomePageURL(for: appDelegate.ghostty).absoluteString
                )
                guard let url = URL(string: normalizedURL) else {
                    return .failure(for: request, error: .invalidRequest("The Browser tab URL is invalid."))
                }
                initialURL = url
            } else {
                initialURL = nil
            }

            let controller = BrowserTabController.newWindow(appDelegate.ghostty, initialURL: initialURL)
            let browserTab = ScriptBrowserTab(controller: controller)
            switch await browserTab.waitForActivePageBridge(timeout: Self.externalCommandTimeout()) {
            case .success:
                break
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.tabSummary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The new Browser tab summary could not be serialized as JSON.")
                )
            }
        case .newContext:
            guard let appDelegate = NSApp.delegate as? AppDelegate else {
                return .failure(for: request, error: .internalFailure("The GhoDex app delegate is unavailable."))
            }

            let contextPolicy: BrowserContextPolicy
            switch BrowserContextPolicy.parse(payload: request.payload) {
            case let .success(parsed):
                contextPolicy = parsed
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            let initialURL: URL?
            if let rawURL = request.payload["url"], !rawURL.isEmpty {
                let normalizedURL = BrowserPaths.normalizedURLString(
                    rawURL,
                    fallback: BrowserTabController.defaultHomePageURL(for: appDelegate.ghostty).absoluteString
                )
                guard let url = URL(string: normalizedURL) else {
                    return .failure(for: request, error: .invalidRequest("The Browser context URL is invalid."))
                }
                initialURL = url
            } else {
                initialURL = nil
            }

            let controller = BrowserTabController.newWindow(
                appDelegate.ghostty,
                initialURL: initialURL,
                contextPolicy: contextPolicy
            )
            let browserTab = ScriptBrowserTab(controller: controller)
            browserTab.prepareForExternalControlStartup()

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.contextSummary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The new Browser context summary could not be serialized as JSON.")
                )
            }
        case .loadURL:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let rawURL = request.payload["url"], !rawURL.isEmpty else {
                return .failure(for: request, error: .invalidRequest("The loadURL command requires a non-empty url payload."))
            }

            switch await target.browserTab.loadAsync(url: rawURL, pageID: target.page.id) {
            case let .success(result):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: ["loaded": result]))
                } catch {
                    return .failure(for: request, error: .internalFailure("The loadURL result could not be serialized as JSON."))
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .getCookies:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch await target.browserTab.getCookiesAsync(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .setCookie:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch await target.browserTab.setCookieAsync(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .deleteCookie:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch await target.browserTab.deleteCookieAsync(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .clearCookies:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch await target.browserTab.clearCookiesAsync(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .evaluateJavaScript:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let script = request.payload["script"], !script.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The evaluateJavaScript command requires a non-empty script payload.")
                )
            }

            switch await target.browserTab.evaluateAsync(javaScript: script, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .runDOMBatch:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let commandsJSON = request.payload["commandsJSON"], !commandsJSON.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The runDOMBatch command requires a non-empty commandsJSON payload.")
                )
            }

            switch await target.browserTab.runDOMBatchAsync(commandsJSON: commandsJSON, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        default:
            return routeExternalCommand(request)
        }
    }

    static func routeExternalCommand(_ request: BrowserExternalCommandRequest) -> BrowserExternalCommandResponse {
        if let versionError = request.validateVersion() {
            return .failure(for: request, error: versionError)
        }

        switch request.command {
        case .listTabs:
            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(from: NSApp.browserTabsForExternalControl.map(\.tabSummary))
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The browser tab list could not be serialized as JSON.")
                )
            }
        case .listContexts:
            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(from: NSApp.browserContextsForExternalControl.map(\.contextSummary))
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The browser context list could not be serialized as JSON.")
                )
            }
        case .getContext:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.contextSummary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The browser context summary could not be serialized as JSON.")
                )
            }
        case .newContext:
            guard let appDelegate = NSApp.delegate as? AppDelegate else {
                return .failure(for: request, error: .internalFailure("The GhoDex app delegate is unavailable."))
            }

            let contextPolicy: BrowserContextPolicy
            switch BrowserContextPolicy.parse(payload: request.payload) {
            case let .success(parsed):
                contextPolicy = parsed
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            let initialURL: URL?
            if let rawURL = request.payload["url"], !rawURL.isEmpty {
                let normalizedURL = BrowserPaths.normalizedURLString(
                    rawURL,
                    fallback: BrowserTabController.defaultHomePageURL(for: appDelegate.ghostty).absoluteString
                )
                guard let url = URL(string: normalizedURL) else {
                    return .failure(for: request, error: .invalidRequest("The Browser context URL is invalid."))
                }
                initialURL = url
            } else {
                initialURL = nil
            }

            let controller = BrowserTabController.newWindow(
                appDelegate.ghostty,
                initialURL: initialURL,
                contextPolicy: contextPolicy
            )
            let browserTab = ScriptBrowserTab(controller: controller)
            controller.model.ensureRuntimeActivationForExternalControl()

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.contextSummary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The new Browser context summary could not be serialized as JSON.")
                )
            }
        case .listPages:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.pageSummaries))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The browser page list could not be serialized as JSON.")
                )
            }
        case .newPageInContext:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            switch browserTab.newPage(initialURL: request.payload["url"]) {
            case let .success(summary):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: summary))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The new Browser page summary could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .getActivePage:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }
            guard let summary = browserTab.activePageSummary else {
                return .failure(for: request, error: .internalFailure("No active browser page is available."))
            }

            do {
                return .success(for: request, resultJSON: try jsonString(from: summary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The active browser page summary could not be serialized as JSON.")
                )
            }
        case .listFrames:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch target.browserTab.listFrames(pageID: target.page.id) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .activatePage:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }
            guard let rawPageID = request.payload["pageID"] ?? request.pageID, !rawPageID.isEmpty else {
                return .failure(for: request, error: .invalidRequest("The activatePage command requires a non-empty pageID payload or pageID field."))
            }

            switch browserTab.activatePage(pageID: rawPageID) {
            case let .success(summary):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: summary))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The activated browser page summary could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .closePage:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            switch browserTab.closePage(pageID: request.payload["pageID"] ?? request.pageID) {
            case let .success(result):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: result))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The Browser page close result could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .activateContext:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            switch browserTab.activateContext() {
            case let .success(summary):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: summary))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The activated Browser context summary could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .closeContext:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserContextID/browserTabID does not resolve to a live Browser context."))
            }

            switch browserTab.closeContext() {
            case let .success(result):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: result))
                } catch {
                    return .failure(
                        for: request,
                        error: .internalFailure("The Browser context close result could not be serialized as JSON.")
                    )
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .getDebugStatus:
            do {
                return .success(for: request, resultJSON: try jsonString(from: debugStatusResult()))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The Browser debug status could not be serialized as JSON.")
                )
            }
        case .query:
            return routeExternalDOMCommand(request, command: .query)
        case .click:
            return routeExternalDOMCommand(request, command: .click)
        case .typeText:
            return routeExternalDOMCommand(request, command: .typeText)
        case .waitForSelector:
            return routeExternalDOMCommand(request, command: .waitForSelector)
        case .getText:
            return routeExternalDOMCommand(request, command: .getText)
        case .getAttributes:
            return routeExternalDOMCommand(request, command: .getAttributes)
        case .getBoundingBox:
            return routeExternalDOMCommand(request, command: .getBoundingBox)
        case .getDOMSnapshot:
            return routeExternalDOMCommand(request, command: .getDOMSnapshot)
        case .newTab:
            let compatibilityRequest = BrowserExternalCommandRequest(
                id: request.id,
                version: request.version,
                command: .newContext,
                browserTabID: request.browserTabID,
                browserContextID: request.browserContextID,
                pageID: request.pageID,
                frameName: request.frameName,
                documentRevision: request.documentRevision,
                payload: request.payload
            )
            let contextResponse = routeExternalCommand(compatibilityRequest)
            guard contextResponse.ok,
                  let resultJSON = contextResponse.resultJSON,
                  let data = resultJSON.data(using: .utf8),
                  let contextSummary = try? JSONDecoder().decode(BrowserExternalContextSummary.self, from: data)
            else {
                return contextResponse
            }

            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(
                        from: BrowserExternalTabSummary(
                            id: contextSummary.id,
                            title: contextSummary.title,
                            url: contextSummary.url
                        )
                    )
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The compatibility Browser tab summary could not be serialized as JSON.")
                )
            }
        case .loadURL:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let rawURL = request.payload["url"], !rawURL.isEmpty else {
                return .failure(for: request, error: .invalidRequest("The loadURL command requires a non-empty url payload."))
            }

            switch target.browserTab.load(url: rawURL, pageID: target.page.id) {
            case let .success(result):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: ["loaded": result]))
                } catch {
                    return .failure(for: request, error: .internalFailure("The loadURL result could not be serialized as JSON."))
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .goBack:
            switch routeExternalDOMCommand(request, command: .goBack) {
            case let response where response.ok:
                do {
                    return .success(for: request, resultJSON: try jsonString(from: BrowserExternalMutationAck(accepted: true, operation: "goBack")))
                } catch {
                    return .failure(for: request, error: .internalFailure("The goBack acknowledgment could not be serialized as JSON."))
                }
            case let response:
                return response
            }
        case .goForward:
            switch routeExternalDOMCommand(request, command: .goForward) {
            case let response where response.ok:
                do {
                    return .success(for: request, resultJSON: try jsonString(from: BrowserExternalMutationAck(accepted: true, operation: "goForward")))
                } catch {
                    return .failure(for: request, error: .internalFailure("The goForward acknowledgment could not be serialized as JSON."))
                }
            case let response:
                return response
            }
        case .reload:
            switch routeExternalDOMCommand(request, command: .reload) {
            case let response where response.ok:
                do {
                    return .success(for: request, resultJSON: try jsonString(from: BrowserExternalMutationAck(accepted: true, operation: "reload")))
                } catch {
                    return .failure(for: request, error: .internalFailure("The reload acknowledgment could not be serialized as JSON."))
                }
            case let response:
                return response
            }
        case .resolveDialog:
            return routeExternalRuntimePromptResolutionCommand(request, command: .resolveDialog)
        case .resolvePermission:
            return routeExternalRuntimePromptResolutionCommand(request, command: .resolvePermission)
        case .resolveAuth:
            return routeExternalRuntimePromptResolutionCommand(request, command: .resolveAuth)
        case .resolveCertificate:
            return routeExternalRuntimePromptResolutionCommand(request, command: .resolveCertificate)
        case .cancelDownload:
            return routeExternalDownloadControlCommand(request, command: .cancelDownload)
        case .getCookies:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch target.browserTab.getCookies(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .setCookie:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch target.browserTab.setCookie(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .deleteCookie:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch target.browserTab.deleteCookie(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .clearCookies:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }

            switch target.browserTab.clearCookies(payload: request.payload, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .evaluateJavaScript:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let script = request.payload["script"], !script.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The evaluateJavaScript command requires a non-empty script payload.")
                )
            }

            switch target.browserTab.evaluate(javaScript: script, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .runDOMBatch:
            let target: ResolvedExternalPageTarget
            switch resolvePageTarget(for: request) {
            case let .success(resolved):
                target = resolved
            case let .failure(error):
                return .failure(for: request, error: error)
            }
            guard let commandsJSON = request.payload["commandsJSON"], !commandsJSON.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The runDOMBatch command requires a non-empty commandsJSON payload.")
                )
            }

            switch target.browserTab.runDOMBatch(commandsJSON: commandsJSON, pageID: target.page.id, frameName: target.frameName) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .subscribeEvents:
            guard let browserTab = browserTab(for: request), let controller = browserTab.controller else {
                return .failure(for: request, error: .invalidRequest("The browserTabID does not resolve to a live Browser tab."))
            }

            let requestedEventKinds: Set<BrowserExternalEventKind>
            do {
                requestedEventKinds = try parseEventKinds(from: request.payload["kindsJSON"])
            } catch let error as BrowserExternalCommandError {
                return .failure(for: request, error: error)
            } catch {
                return .failure(for: request, error: .invalidRequest("The event kinds payload is invalid."))
            }

            do {
                let subscription = BrowserExternalEventBroker.shared.subscribe(
                    to: controller,
                    kinds: requestedEventKinds,
                    version: request.version
                )
                return .success(for: request, resultJSON: try jsonString(from: subscription))
            } catch let error as BrowserExternalCommandError {
                return .failure(for: request, error: error)
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The event subscription result could not be serialized as JSON.")
                )
            }
        case .drainEvents:
            let requestedSubscriptionID: UUID
            do {
                requestedSubscriptionID = try parseSubscriptionID(from: request)
            } catch let error as BrowserExternalCommandError {
                return .failure(for: request, error: error)
            } catch {
                return .failure(for: request, error: .invalidRequest("The event subscription identifier is invalid."))
            }

            let limit: Int?
            do {
                limit = try drainLimit(from: request.payload["limit"])
            } catch let error as BrowserExternalCommandError {
                return .failure(for: request, error: error)
            } catch {
                return .failure(for: request, error: .invalidRequest("The event drain limit is invalid."))
            }

            guard let result = BrowserExternalEventBroker.shared.drain(
                subscriptionID: requestedSubscriptionID,
                limit: limit,
                version: request.version
            ) else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The subscriptionID does not resolve to a live browser event subscription.")
                )
            }

            do {
                return .success(for: request, resultJSON: try jsonString(from: result))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The drained browser events could not be serialized as JSON.")
                )
            }
        case .unsubscribeEvents:
            let requestedSubscriptionID: UUID
            do {
                requestedSubscriptionID = try parseSubscriptionID(from: request)
            } catch let error as BrowserExternalCommandError {
                return .failure(for: request, error: error)
            } catch {
                return .failure(for: request, error: .invalidRequest("The event subscription identifier is invalid."))
            }

            guard BrowserExternalEventBroker.shared.unsubscribe(subscriptionID: requestedSubscriptionID) else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The subscriptionID does not resolve to a live browser event subscription.")
                )
            }

            do {
                return .success(
                    for: request,
                    resultJSON: try jsonString(from: BrowserExternalSubscriptionAck(version: request.version))
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The event unsubscription acknowledgment could not be serialized as JSON.")
                )
            }
        }
    }

    static func browserTab(for request: BrowserExternalCommandRequest) -> ScriptBrowserTab? {
        guard let browserContextID = request.resolvedBrowserContextID else {
            return nil
        }
        return NSApp.browserContextsForExternalControl.first(where: { $0.stableID == browserContextID })
    }

    private static func debugStatusResult() -> BrowserExternalDebugStatusResult {
        let configuredPort: Int
        if BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() {
            configuredPort = UserDefaults.standard.integer(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
        } else {
            configuredPort = 0
        }
        let enabledPort = (1...65535).contains(configuredPort) ? configuredPort : nil

        return BrowserExternalDebugStatusResult(
            enabled: enabledPort != nil,
            port: enabledPort,
            source: enabledPort == nil ? "disabled" : "config",
            cefInitialized: GhoDexCEFIsInitialized(),
            runtimeAvailable: GhoDexCEFBuildHasRuntime()
        )
    }

    private static func jsonString<T: Encodable>(from value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw BrowserExternalCommandError.internalFailure("The browser command protocol payload could not be serialized as UTF-8.")
        }
        return encoded
    }

    private static func parseEventKinds(from kindsJSON: String?) throws -> Set<BrowserExternalEventKind> {
        guard let kindsJSON, !kindsJSON.isEmpty else {
            return []
        }

        guard let data = kindsJSON.data(using: .utf8) else {
            throw BrowserExternalCommandError.invalidRequest("The kindsJSON payload must be valid UTF-8 JSON.")
        }

        do {
            let decoded = try JSONDecoder().decode([BrowserExternalEventKind].self, from: data)
            return Set(decoded)
        } catch {
            throw BrowserExternalCommandError.invalidRequest(
                "The kindsJSON payload must decode to a JSON array of browser event kinds."
            )
        }
    }

    private static func parseSubscriptionID(from request: BrowserExternalCommandRequest) throws -> UUID {
        guard let rawSubscriptionID = request.payload["subscriptionID"], !rawSubscriptionID.isEmpty else {
            throw BrowserExternalCommandError.invalidRequest(
                "The \(request.command.rawValue) command requires a subscriptionID payload."
            )
        }

        guard let subscriptionID = UUID(uuidString: rawSubscriptionID) else {
            throw BrowserExternalCommandError.invalidRequest("The subscriptionID payload must be a UUID string.")
        }

        return subscriptionID
    }

    private static func drainLimit(from rawLimit: String?) throws -> Int? {
        guard let rawLimit, !rawLimit.isEmpty else {
            return nil
        }

        guard let limit = Int(rawLimit), limit >= 0 else {
            throw BrowserExternalCommandError.invalidRequest("The limit payload must be a non-negative integer.")
        }

        return limit
    }

    private static func cookieInspectionScript(payload: [String: String]) -> Result<String, BrowserControlError> {
        let appliedFilters: [String: String] = Dictionary(
            uniqueKeysWithValues: payload.compactMap { key, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                switch key {
                case "name", "domain", "url":
                    return (key, trimmed)
                default:
                    return nil
                }
            }
        )

        do {
            let filtersJSON = try jsonString(from: appliedFilters)
            let script = """
(() => {
  const filters = \(filtersJSON);
  const href = String(location.href ?? "");
  const hostname = String(location.hostname ?? "");
  const cookieHeader = String(document.cookie ?? "");
  const entries = cookieHeader
    ? cookieHeader.split(";").map((part) => {
        const trimmed = part.trim();
        const equalsIndex = trimmed.indexOf("=");
        if (equalsIndex === -1) {
          return { name: trimmed, value: "" };
        }
        return {
          name: trimmed.slice(0, equalsIndex),
          value: trimmed.slice(equalsIndex + 1),
        };
      })
    : [];

  const requestedDomain = typeof filters.domain === "string" ? filters.domain.toLowerCase() : null;
  const hostMatchesDomain = !requestedDomain
    || hostname.toLowerCase() === requestedDomain
    || hostname.toLowerCase().endsWith("." + requestedDomain);

  const requestedURL = typeof filters.url === "string" ? filters.url : null;
  const requestedName = typeof filters.name === "string" ? filters.name : null;

  const cookies = entries.filter((entry) => {
    if (requestedURL && href !== requestedURL) return false;
    if (!hostMatchesDomain) return false;
    if (requestedName && entry.name !== requestedName) return false;
    return true;
  });

  return {
    url: href,
    domain: hostname,
    cookieHeader,
    appliedFilters: filters,
    cookies,
  };
})()
"""
            return .success(script)
        } catch {
            return .failure(.internalFailure("The Browser cookie inspection payload could not be serialized."))
        }
    }

    private enum CookieMutationOperation: String {
        case set
        case delete
        case clear
    }

    private static func cookieMutationScript(
        operation: CookieMutationOperation,
        payload: [String: String]
    ) -> Result<String, BrowserControlError> {
        let normalizedPayload: [String: String]
        switch normalizedCookieMutationPayload(operation: operation, payload: payload) {
        case let .success(result):
            normalizedPayload = result
        case let .failure(error):
            return .failure(error)
        }

        do {
            let payloadJSON = try jsonString(from: normalizedPayload)
            let operationJSON = try jsonStringLiteral(operation.rawValue)
            let script = """
(() => {
  const input = \(payloadJSON);
  const operation = \(operationJSON);
  const href = String(location.href ?? "");
  const hostname = String(location.hostname ?? "");
  const currentPath = String(location.pathname ?? "/");
  const currentDirectory = (() => {
    if (!currentPath || currentPath === "/") return "/";
    const lastSlash = currentPath.lastIndexOf("/");
    if (lastSlash <= 0) return "/";
    return currentPath.slice(0, lastSlash + 1);
  })();
  const cookieEntries = () => {
    const header = String(document.cookie ?? "");
    const cookies = header
      ? header.split(";").map((part) => {
          const trimmed = part.trim();
          const equalsIndex = trimmed.indexOf("=");
          if (equalsIndex === -1) {
            return { name: trimmed, value: "" };
          }
          return {
            name: trimmed.slice(0, equalsIndex),
            value: trimmed.slice(equalsIndex + 1),
          };
        })
      : [];
    return { header, cookies };
  };
  const serializeCookie = (name, value, options = {}) => {
    const parts = [`${name}=${encodeURIComponent(String(value ?? ""))}`];
    if (options.path) parts.push(`Path=${options.path}`);
    if (options.domain) parts.push(`Domain=${options.domain}`);
    if (options.maxAge) parts.push(`Max-Age=${options.maxAge}`);
    if (options.expires) parts.push(`Expires=${options.expires}`);
    if (options.sameSite) parts.push(`SameSite=${options.sameSite}`);
    if (options.secure) parts.push("Secure");
    return parts.join("; ");
  };
  const expireCookie = (name, options = {}) => {
    document.cookie = serializeCookie(name, "", {
      path: options.path,
      domain: options.domain,
      expires: "Thu, 01 Jan 1970 00:00:00 GMT",
      maxAge: "0",
    });
  };
  const pathCandidates = (() => {
    const candidates = [];
    const pushPath = (value) => {
      if (typeof value !== "string") return;
      const trimmed = value.trim();
      if (!trimmed || candidates.includes(trimmed)) return;
      candidates.push(trimmed);
    };
    pushPath(input.path);
    pushPath("/");
    pushPath(currentDirectory);
    pushPath(currentPath);
    return candidates.length ? candidates : ["/"];
  })();

  let changedNames = [];
  if (operation === "set") {
    document.cookie = serializeCookie(input.name, input.value ?? "", {
      path: input.path || "/",
      domain: input.domain,
      expires: input.expires,
      maxAge: input.maxAge,
      sameSite: input.sameSite,
      secure: input.secure === "true",
    });
    changedNames = [input.name];
  } else if (operation === "delete") {
    for (const path of pathCandidates) {
      expireCookie(input.name, { path, domain: input.domain });
    }
    changedNames = [input.name];
  } else if (operation === "clear") {
    const before = cookieEntries().cookies;
    changedNames = before.map((entry) => entry.name);
    for (const entry of before) {
      for (const path of pathCandidates) {
        expireCookie(entry.name, { path, domain: input.domain });
      }
    }
  } else {
    throw new Error(`Unsupported cookie mutation operation: ${operation}`);
  }

  const after = cookieEntries();
  return {
    operation,
    url: href,
    domain: hostname,
    cookieHeader: after.header,
    appliedPayload: input,
    changedCount: changedNames.length,
    changedNames,
    cookies: after.cookies,
  };
})()
"""
            return .success(script)
        } catch {
            return .failure(.internalFailure("The Browser cookie mutation payload could not be serialized."))
        }
    }

    private static func normalizedCookieMutationPayload(
        operation: CookieMutationOperation,
        payload: [String: String]
    ) -> Result<[String: String], BrowserControlError> {
        let normalized: [String: String] = Dictionary(
            uniqueKeysWithValues: payload.compactMap { key, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                switch key {
                case "name", "value", "domain", "path", "expires", "maxAge", "sameSite", "secure":
                    return (key, trimmed)
                default:
                    return nil
                }
            }
        )

        switch operation {
        case .set:
            guard let name = normalized["name"], !name.isEmpty else {
                return .failure(.invalidRequest("The setCookie command requires a non-empty name payload."))
            }

            if let secure = normalized["secure"], secure != "true", secure != "false" {
                return .failure(.invalidRequest("The secure payload must be 'true' or 'false' when provided."))
            }

            if let maxAge = normalized["maxAge"], Int(maxAge) == nil {
                return .failure(.invalidRequest("The maxAge payload must be an integer when provided."))
            }

            if let sameSite = normalized["sameSite"] {
                let allowed = Set(["Lax", "Strict", "None"])
                guard allowed.contains(sameSite) else {
                    return .failure(.invalidRequest("The sameSite payload must be one of Lax, Strict, or None."))
                }
            }

            var result = normalized
            result["name"] = name
            if result["path"] == nil {
                result["path"] = "/"
            }
            return .success(result)
        case .delete:
            guard let name = normalized["name"], !name.isEmpty else {
                return .failure(.invalidRequest("The deleteCookie command requires a non-empty name payload."))
            }

            var result: [String: String] = [:]
            result["name"] = name
            if let domain = normalized["domain"] {
                result["domain"] = domain
            }
            if let path = normalized["path"] {
                result["path"] = path
            }
            return .success(result)
        case .clear:
            var result: [String: String] = [:]
            if let domain = normalized["domain"] {
                result["domain"] = domain
            }
            if let path = normalized["path"] {
                result["path"] = path
            }
            return .success(result)
        }
    }

    private static func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw BrowserControlError.internalFailure("The Browser command string literal could not be serialized as UTF-8.")
        }
        return encoded
    }
}

private extension BrowserControlError {
    var externalCommandError: BrowserExternalCommandError {
        BrowserExternalCommandError(code: code.rawValue, message: message, isRetryable: isRetryable)
    }
}

private extension BrowserExternalCommandResponse {
    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw BrowserExternalCommandError.internalFailure("The browser command response could not be serialized as UTF-8.")
        }
        return encoded
    }
}

@MainActor
@objc(GhosttyScriptBrowserLoadURLCommand)
final class ScriptBrowserLoadURLCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard NSApp.validateScript(command: self) else { return nil }

        guard let rawURL = directParameter as? String, !rawURL.isEmpty else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser tab URL."
            return nil
        }

        guard let browserTab = evaluatedArguments?["browserTab"] as? ScriptBrowserTab else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser tab target."
            return nil
        }

        switch browserTab.load(url: rawURL) {
        case let .success(value):
            return NSNumber(value: value)
        case let .failure(error):
            apply(error)
            return nil
        }
    }

    private func apply(_ error: BrowserControlError) {
        scriptErrorNumber = error.code == .invalidRequest ? errAECoercionFail : errAEEventFailed
        scriptErrorString = error.message
    }
}

@MainActor
@objc(GhosttyScriptBrowserEvaluateCommand)
final class ScriptBrowserEvaluateCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard NSApp.validateScript(command: self) else { return nil }

        guard let script = directParameter as? String, !script.isEmpty else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser JavaScript source."
            return nil
        }

        guard let browserTab = evaluatedArguments?["browserTab"] as? ScriptBrowserTab else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser tab target."
            return nil
        }

        switch browserTab.evaluate(javaScript: script) {
        case let .success(resultJSON):
            return resultJSON
        case let .failure(error):
            apply(error)
            return nil
        }
    }

    private func apply(_ error: BrowserControlError) {
        scriptErrorNumber = error.code == .invalidRequest ? errAECoercionFail : errAEEventFailed
        scriptErrorString = error.message
    }
}

@MainActor
@objc(GhosttyScriptBrowserDOMBatchCommand)
final class ScriptBrowserDOMBatchCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard NSApp.validateScript(command: self) else { return nil }

        guard let commandsJSON = directParameter as? String, !commandsJSON.isEmpty else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser DOM batch JSON."
            return nil
        }

        guard let browserTab = evaluatedArguments?["browserTab"] as? ScriptBrowserTab else {
            scriptErrorNumber = errAEParamMissed
            scriptErrorString = "Missing Browser tab target."
            return nil
        }

        switch browserTab.runDOMBatch(commandsJSON: commandsJSON) {
        case let .success(resultJSON):
            return resultJSON
        case let .failure(error):
            apply(error)
            return nil
        }
    }

    private func apply(_ error: BrowserControlError) {
        scriptErrorNumber = error.code == .invalidRequest ? errAECoercionFail : errAEEventFailed
        scriptErrorString = error.message
    }
}
