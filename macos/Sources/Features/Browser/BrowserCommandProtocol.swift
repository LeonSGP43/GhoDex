import Foundation

enum BrowserCommandProtocolVersion {
    static let v1 = "browser.tab.v1"
}

enum BrowserExternalCommandKind: String, Codable, Hashable {
    case listTabs
    case newTab
    case listPages
    case getActivePage
    case activatePage
    case listFrames
    case getDebugStatus
    case loadURL
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
}

enum BrowserExternalEventKind: String, Codable, Hashable {
    case consoleMessage
    case bridgeReady
    case navigationStateChanged
    case pageTitleChanged
    case networkRequestFinished
    case pageInspectionSnapshot
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
    let pageID: String?
    let frameName: String?
    let documentRevision: Int?
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        version: String = BrowserCommandProtocolVersion.v1,
        command: BrowserExternalCommandKind,
        browserTabID: String? = nil,
        pageID: String? = nil,
        frameName: String? = nil,
        documentRevision: Int? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.version = version
        self.command = command
        self.browserTabID = browserTabID
        self.pageID = pageID
        self.frameName = frameName
        self.documentRevision = documentRevision
        self.payload = payload
    }

    func validateVersion() -> BrowserExternalCommandError? {
        guard version == BrowserCommandProtocolVersion.v1 else {
            return .unsupportedVersion(
                "The browser command protocol version \(version) is not supported. Expected \(BrowserCommandProtocolVersion.v1)."
            )
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
            version: BrowserCommandProtocolVersion.v1,
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
            version: BrowserCommandProtocolVersion.v1,
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

struct BrowserExternalEventEnvelope: Identifiable, Hashable, Codable {
    let id: UUID
    let version: String
    let subscriptionID: UUID
    let browserTabID: String
    let kind: BrowserExternalEventKind
    let payload: [String: String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        version: String = BrowserCommandProtocolVersion.v1,
        subscriptionID: UUID,
        browserTabID: String,
        kind: BrowserExternalEventKind,
        payload: [String: String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.version = version
        self.subscriptionID = subscriptionID
        self.browserTabID = browserTabID
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
