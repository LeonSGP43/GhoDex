import AppKit
import Foundation

/// AppleScript-facing wrapper around one Browser tab controller.
///
/// The scripting surface intentionally targets the active page inside the
/// browser tab model so command-style automation can control the visible page
/// without leaking the internal page-stack implementation into AppleScript.
@MainActor
@objc(GhosttyScriptBrowserTab)
final class ScriptBrowserTab: NSObject {
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

    fileprivate func load(url rawURL: String) -> Result<Bool, BrowserControlError> {
        awaitControlResult { completion in
            guard let controller, let activePage = controller.model.activePage else {
                completion(.failure(.pageNotFound("No active browser page is available.")))
                return
            }

            let normalizedURL = BrowserPaths.normalizedURLString(rawURL, fallback: controller.model.displayedURL)
            activePage.send(.loadURL, payload: ["url": normalizedURL]) { response in
                if let error = response.error {
                    completion(.failure(error))
                    return
                }

                completion(.success(true))
            }
        }
    }

    fileprivate func evaluate(javaScript script: String) -> Result<String, BrowserControlError> {
        awaitControlResult { completion in
            guard let controller, let activePage = controller.model.activePage else {
                completion(.failure(.pageNotFound("No active browser page is available.")))
                return
            }

            activePage.send(.evaluateJavaScript, payload: ["script": script]) { response in
                if let error = response.error {
                    completion(.failure(error))
                    return
                }

                completion(.success(response.valueJSON ?? "null"))
            }
        }
    }

    fileprivate func runDOMBatch(commandsJSON: String) -> Result<String, BrowserControlError> {
        let commands: [BrowserDOMBatchCommand]
        do {
            guard let data = commandsJSON.data(using: .utf8) else {
                return .failure(.invalidRequest("The DOM batch JSON must be valid UTF-8 text."))
            }
            commands = try JSONDecoder().decode([BrowserDOMBatchCommand].self, from: data)
        } catch {
            return .failure(.invalidRequest("The DOM batch JSON must decode to an array of browser DOM batch commands."))
        }

        return awaitControlResult { completion in
            guard let controller, let activePage = controller.model.activePage else {
                completion(.failure(.pageNotFound("No active browser page is available.")))
                return
            }

            activePage.runDecodedDOMCommandBatch(commands) { result in
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
    }

    private func awaitControlResult<T>(
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
}

extension ScriptBrowserTab {
    static func stableID(controller: BrowserTabController) -> String {
        "browser-tab-\(ObjectIdentifier(controller).hexString)"
    }

    var tabSummary: BrowserExternalTabSummary {
        BrowserExternalTabSummary(id: stableID, title: title, url: url)
    }

    static func runExternalCommandProtocol(requestJSON: String) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let requestData = requestJSON.data(using: .utf8) else {
            throw BrowserExternalCommandError.invalidRequest("The browser command protocol request must be valid UTF-8 JSON.")
        }

        let request: BrowserExternalCommandRequest
        do {
            request = try decoder.decode(BrowserExternalCommandRequest.self, from: requestData)
        } catch {
            throw BrowserExternalCommandError.invalidRequest("The browser command protocol request could not be decoded.")
        }

        let response = routeExternalCommand(request)
        return try response.jsonString()
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
                    resultJSON: try jsonString(from: NSApp.browserTabs.map(\.tabSummary))
                )
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The browser tab list could not be serialized as JSON.")
                )
            }
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

            do {
                return .success(for: request, resultJSON: try jsonString(from: browserTab.tabSummary))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The new Browser tab summary could not be serialized as JSON.")
                )
            }
        case .loadURL:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserTabID does not resolve to a live Browser tab."))
            }
            guard let rawURL = request.payload["url"], !rawURL.isEmpty else {
                return .failure(for: request, error: .invalidRequest("The loadURL command requires a non-empty url payload."))
            }

            switch browserTab.load(url: rawURL) {
            case let .success(result):
                do {
                    return .success(for: request, resultJSON: try jsonString(from: ["loaded": result]))
                } catch {
                    return .failure(for: request, error: .internalFailure("The loadURL result could not be serialized as JSON."))
                }
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .evaluateJavaScript:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserTabID does not resolve to a live Browser tab."))
            }
            guard let script = request.payload["script"], !script.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The evaluateJavaScript command requires a non-empty script payload.")
                )
            }

            switch browserTab.evaluate(javaScript: script) {
            case let .success(resultJSON):
                return .success(for: request, resultJSON: resultJSON)
            case let .failure(error):
                return .failure(for: request, error: error.externalCommandError)
            }
        case .runDOMBatch:
            guard let browserTab = browserTab(for: request) else {
                return .failure(for: request, error: .invalidRequest("The browserTabID does not resolve to a live Browser tab."))
            }
            guard let commandsJSON = request.payload["commandsJSON"], !commandsJSON.isEmpty else {
                return .failure(
                    for: request,
                    error: .invalidRequest("The runDOMBatch command requires a non-empty commandsJSON payload.")
                )
            }

            switch browserTab.runDOMBatch(commandsJSON: commandsJSON) {
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
                let subscription = BrowserExternalEventBroker.shared.subscribe(to: controller, kinds: requestedEventKinds)
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

            guard let result = BrowserExternalEventBroker.shared.drain(subscriptionID: requestedSubscriptionID, limit: limit) else {
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
                return .success(for: request, resultJSON: try jsonString(from: BrowserExternalSubscriptionAck()))
            } catch {
                return .failure(
                    for: request,
                    error: .internalFailure("The event unsubscription acknowledgment could not be serialized as JSON.")
                )
            }
        }
    }

    static func browserTab(for request: BrowserExternalCommandRequest) -> ScriptBrowserTab? {
        guard let browserTabID = request.browserTabID, !browserTabID.isEmpty else {
            return nil
        }
        return NSApp.browserTabs.first(where: { $0.stableID == browserTabID })
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
