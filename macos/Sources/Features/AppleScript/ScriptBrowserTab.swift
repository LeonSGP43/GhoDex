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
