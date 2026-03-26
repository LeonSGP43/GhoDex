import Foundation

enum BrowserCommandProtocolVersion {
    static let v1 = "browser.tab.v1"
    static let v2 = "browser.context.v2"

    static let supportedVersions: Set<String> = [v1, v2]
}

enum BrowserExternalCommandKind: String, Codable, Hashable {
    case listTabs
    case newTab
    case listContexts
    case getContext
    case newContext
    case closeContext
    case activateContext
    case listPages
    case newPageInContext
    case getActivePage
    case activatePage
    case closePage
    case listFrames
    case getDebugStatus
    case loadURL
    case goBack
    case goForward
    case reload
    case getCookies
    case setCookie
    case deleteCookie
    case clearCookies
    case evaluateJavaScript
    case query
    case click
    case typeText
    case waitForSelector
    case getText
    case getAttributes
    case getBoundingBox
    case getDOMSnapshot
    case runDOMBatch
    case subscribeEvents
    case drainEvents
    case unsubscribeEvents
    case resolveDialog
    case resolvePermission
    case resolveAuth
    case resolveCertificate
}

enum BrowserExternalEventKind: String, Codable, Hashable {
    case consoleMessage
    case bridgeReady
    case navigationStateChanged
    case pageTitleChanged
    case networkRequestFinished
    case popupRequest
    case pageInspectionSnapshot
    case download
    case javaScriptDialog
    case permissionRequest
    case authenticationRequest
    case certificateWarning
}

struct BrowserExternalCommandError: Error, Hashable, Codable {
    let code: String
    let message: String
    let isRetryable: Bool

    init(code: String, message: String, isRetryable: Bool = false) {
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }

    static func invalidRequest(_ message: String) -> BrowserExternalCommandError {
        BrowserExternalCommandError(code: "invalid_request", message: message)
    }

    static func unsupportedVersion(_ message: String) -> BrowserExternalCommandError {
        BrowserExternalCommandError(code: "unsupported_version", message: message)
    }

    static func internalFailure(_ message: String) -> BrowserExternalCommandError {
        BrowserExternalCommandError(code: "internal_failure", message: message)
    }

    static func staleDocumentRevision(_ message: String) -> BrowserExternalCommandError {
        BrowserExternalCommandError(code: "stale_document_revision", message: message, isRetryable: true)
    }
}

struct BrowserExternalCommandRequest: Identifiable, Hashable, Codable {
    let id: UUID
    let version: String
    let command: BrowserExternalCommandKind
    let browserTabID: String?
    let browserContextID: String?
    let pageID: String?
    let frameName: String?
    let documentRevision: Int?
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        version: String = BrowserCommandProtocolVersion.v1,
        command: BrowserExternalCommandKind,
        browserTabID: String? = nil,
        browserContextID: String? = nil,
        pageID: String? = nil,
        frameName: String? = nil,
        documentRevision: Int? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.version = version
        self.command = command
        self.browserTabID = browserTabID
        self.browserContextID = browserContextID
        self.pageID = pageID
        self.frameName = frameName
        self.documentRevision = documentRevision
        self.payload = payload
    }

    func validateVersion() -> BrowserExternalCommandError? {
        guard BrowserCommandProtocolVersion.supportedVersions.contains(version) else {
            return .unsupportedVersion(
                "The browser command protocol version \(version) is not supported. Expected one of \(BrowserCommandProtocolVersion.supportedVersions.sorted())."
            )
        }

        return nil
    }

    var resolvedBrowserContextID: String? {
        if let browserContextID = browserContextID?.trimmingCharacters(in: .whitespacesAndNewlines), !browserContextID.isEmpty {
            return browserContextID
        }
        if let browserTabID = browserTabID?.trimmingCharacters(in: .whitespacesAndNewlines), !browserTabID.isEmpty {
            return browserTabID
        }
        return nil
    }
}

struct BrowserExternalCommandResponse: Hashable, Codable {
    let id: UUID
    let version: String
    let ok: Bool
    let resultJSON: String?
    let error: BrowserExternalCommandError?

    static func success(
        for request: BrowserExternalCommandRequest,
        resultJSON: String? = nil
    ) -> BrowserExternalCommandResponse {
        BrowserExternalCommandResponse(
            id: request.id,
            version: request.version,
            ok: true,
            resultJSON: resultJSON,
            error: nil
        )
    }

    static func failure(
        for request: BrowserExternalCommandRequest,
        error: BrowserExternalCommandError
    ) -> BrowserExternalCommandResponse {
        BrowserExternalCommandResponse(
            id: request.id,
            version: request.version,
            ok: false,
            resultJSON: nil,
            error: error
        )
    }
}

struct BrowserExternalTabSummary: Hashable, Codable {
    let id: String
    let title: String
    let url: String
}

struct BrowserExternalContextSummary: Hashable, Codable {
    let id: String
    let title: String
    let url: String
    let activePageID: String?
    let pageCount: Int
    let isFrontmost: Bool
}

struct BrowserExternalPageSummary: Hashable, Codable {
    let id: String
    let title: String
    let url: String
    let isActive: Bool
    let documentRevision: Int
}

struct BrowserExternalFrameSummary: Hashable, Codable {
    let name: String
    let url: String
    let isMainFrame: Bool
}

struct BrowserExternalDebugStatusResult: Hashable, Codable {
    let enabled: Bool
    let port: Int?
    let source: String
    let cefInitialized: Bool
    let runtimeAvailable: Bool
}

struct BrowserExternalCookieEntry: Hashable, Codable {
    let name: String
    let value: String
}

struct BrowserExternalCookieInspectionResult: Hashable, Codable {
    let url: String
    let domain: String
    let cookieHeader: String
    let appliedFilters: [String: String]
    let cookies: [BrowserExternalCookieEntry]
}

struct BrowserExternalCookieMutationResult: Hashable, Codable {
    let operation: String
    let url: String
    let domain: String
    let cookieHeader: String
    let appliedPayload: [String: String]
    let changedCount: Int
    let changedNames: [String]
    let cookies: [BrowserExternalCookieEntry]
}

struct BrowserExternalMutationAck: Hashable, Codable {
    let accepted: Bool
    let operation: String
}

enum BrowserRuntimePromptResolutionKind: String, Codable, Hashable {
    case dialog
    case permission
    case auth
    case certificate
}

struct BrowserRuntimePromptResolutionRequest: Hashable, Codable {
    let requestID: String
    let kind: BrowserRuntimePromptResolutionKind
    let accepted: Bool?
    let result: String?
    let userInput: String?
    let username: String?
    let password: String?

    var controlPayload: [String: String] {
        var payload = ["requestID": requestID]
        if let accepted {
            payload["accepted"] = accepted ? "true" : "false"
        }
        if let result, !result.isEmpty {
            payload["result"] = result
        }
        if let userInput {
            payload["userInput"] = userInput
        }
        if let username {
            payload["username"] = username
        }
        if let password {
            payload["password"] = password
        }
        return payload
    }

    static func from(
        command: BrowserExternalCommandKind,
        payload: [String: String]
    ) throws -> BrowserRuntimePromptResolutionRequest {
        switch command {
        case .resolveDialog:
            return try dialog(from: payload)
        case .resolvePermission:
            return try permission(from: payload)
        case .resolveAuth:
            return try auth(from: payload)
        case .resolveCertificate:
            return try certificate(from: payload)
        default:
            throw BrowserExternalCommandError.invalidRequest(
                "The \(command.rawValue) command is not a runtime prompt resolution command."
            )
        }
    }

    static func dialog(from payload: [String: String]) throws -> BrowserRuntimePromptResolutionRequest {
        BrowserRuntimePromptResolutionRequest(
            requestID: try requestID(from: payload),
            kind: .dialog,
            accepted: try requiredBoolean(key: "accepted", from: payload),
            result: nil,
            userInput: payload["userInput"],
            username: nil,
            password: nil
        )
    }

    static func permission(from payload: [String: String]) throws -> BrowserRuntimePromptResolutionRequest {
        let result = try requiredString(key: "result", from: payload)
        guard ["allow", "deny", "dismiss"].contains(result) else {
            throw BrowserExternalCommandError.invalidRequest(
                "The resolvePermission command requires result to be one of allow, deny, or dismiss."
            )
        }
        return BrowserRuntimePromptResolutionRequest(
            requestID: try requestID(from: payload),
            kind: .permission,
            accepted: nil,
            result: result,
            userInput: nil,
            username: nil,
            password: nil
        )
    }

    static func auth(from payload: [String: String]) throws -> BrowserRuntimePromptResolutionRequest {
        BrowserRuntimePromptResolutionRequest(
            requestID: try requestID(from: payload),
            kind: .auth,
            accepted: try requiredBoolean(key: "accepted", from: payload),
            result: nil,
            userInput: nil,
            username: payload["username"],
            password: payload["password"]
        )
    }

    static func certificate(from payload: [String: String]) throws -> BrowserRuntimePromptResolutionRequest {
        BrowserRuntimePromptResolutionRequest(
            requestID: try requestID(from: payload),
            kind: .certificate,
            accepted: try requiredBoolean(key: "accepted", from: payload),
            result: nil,
            userInput: nil,
            username: nil,
            password: nil
        )
    }

    private static func requestID(from payload: [String: String]) throws -> String {
        try requiredString(key: "requestID", from: payload)
    }

    private static func requiredString(key: String, from payload: [String: String]) throws -> String {
        guard let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw BrowserExternalCommandError.invalidRequest("The \(key) payload is required.")
        }
        return value
    }

    private static func requiredBoolean(key: String, from payload: [String: String]) throws -> Bool {
        let value = try requiredString(key: key, from: payload).lowercased()
        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            throw BrowserExternalCommandError.invalidRequest("The \(key) payload must be true or false.")
        }
    }
}

struct BrowserExternalRuntimeResolutionAck: Hashable, Codable {
    let requestID: String
    let kind: BrowserRuntimePromptResolutionKind
    let resolved: Bool
}

struct BrowserExternalPageCloseResult: Hashable, Codable {
    let closedPageID: String
    let remainingPageCount: Int
    let activePageID: String?
}

struct BrowserExternalContextCloseResult: Hashable, Codable {
    let closedContextID: String
    let closedPageCount: Int
}

struct BrowserExternalEventEnvelope: Identifiable, Hashable, Codable {
    let id: UUID
    let version: String
    let subscriptionID: UUID
    let browserTabID: String
    let browserContextID: String
    let kind: BrowserExternalEventKind
    let payload: [String: String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        version: String = BrowserCommandProtocolVersion.v1,
        subscriptionID: UUID,
        browserTabID: String,
        browserContextID: String? = nil,
        kind: BrowserExternalEventKind,
        payload: [String: String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.version = version
        self.subscriptionID = subscriptionID
        self.browserTabID = browserTabID
        self.browserContextID = browserContextID ?? browserTabID
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}

struct BrowserExternalEventSubscriptionResult: Hashable, Codable {
    let version: String
    let subscriptionID: UUID
    let nextCursor: Int

    init(
        version: String = BrowserCommandProtocolVersion.v1,
        subscriptionID: UUID,
        nextCursor: Int = 0
    ) {
        self.version = version
        self.subscriptionID = subscriptionID
        self.nextCursor = nextCursor
    }
}

struct BrowserExternalEventDrainResult: Hashable, Codable {
    let version: String
    let subscriptionID: UUID
    let nextCursor: Int
    let droppedCount: Int
    let events: [BrowserExternalEventEnvelope]

    init(
        version: String = BrowserCommandProtocolVersion.v1,
        subscriptionID: UUID,
        nextCursor: Int,
        droppedCount: Int,
        events: [BrowserExternalEventEnvelope]
    ) {
        self.version = version
        self.subscriptionID = subscriptionID
        self.nextCursor = nextCursor
        self.droppedCount = droppedCount
        self.events = events
    }
}

struct BrowserExternalSubscriptionAck: Hashable, Codable {
    let version: String
    let ok: Bool

    init(
        version: String = BrowserCommandProtocolVersion.v1,
        ok: Bool = true
    ) {
        self.version = version
        self.ok = ok
    }
}
