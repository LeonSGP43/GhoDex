import Foundation

enum ControlHarnessAuthScope: String, Codable, CaseIterable, Sendable {
    case observe
    case mutate
}

struct ControlHarnessPairingBeginResult: Encodable, Sendable {
    let pairingCode: String
    let client: String
    let scopes: [String]
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case client
        case scopes
        case expiresAt = "expires_at"
    }
}

struct ControlHarnessTokenIssueResult: Encodable, Sendable {
    let token: String
    let tokenID: String
    let client: String
    let scopes: [String]
    let issuedAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case tokenID = "token_id"
        case client
        case scopes
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
    }
}

struct ControlHarnessTokenStatusResult: Encodable, Sendable {
    let tokenID: String
    let client: String
    let scopes: [String]
    let issuedAt: String
    let expiresAt: String
    let revokedAt: String?

    enum CodingKeys: String, CodingKey {
        case tokenID = "token_id"
        case client
        case scopes
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }
}

actor ControlHarnessAuth {
    struct Configuration: Sendable {
        var pairingCodeTTLSeconds: TimeInterval = 300
        var tokenTTLSeconds: TimeInterval = 86_400

        static func environment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Self {
            var configuration = Self()
            if let value = parseDouble(environment["GHODEX_CONTROL_HARNESS_PAIRING_CODE_TTL_SECONDS"]) {
                configuration.pairingCodeTTLSeconds = max(1, value)
            }
            if let value = parseDouble(environment["GHODEX_CONTROL_HARNESS_TOKEN_TTL_SECONDS"]) {
                configuration.tokenTTLSeconds = max(1, value)
            }
            return configuration
        }

        private static func parseDouble(_ rawValue: String?) -> Double? {
            guard let rawValue else { return nil }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return Double(trimmed)
        }
    }

    struct Grant: Sendable {
        let tokenID: String
        let client: String
        let scopes: Set<ControlHarnessAuthScope>
        let issuedAt: Date
        let expiresAt: Date
    }

    enum Validation: Sendable {
        case allow(Grant)
        case deny(errorCode: String, errorMessage: String)
    }

    private struct PairingRecord: Sendable {
        let pairingCode: String
        let client: String
        let scopes: Set<ControlHarnessAuthScope>
        let createdAt: Date
        let expiresAt: Date
    }

    private struct PersistedState: Codable {
        var tokens: [StoredToken]
    }

    private struct StoredToken: Codable, Sendable {
        var token: String
        var tokenID: String
        var client: String
        var scopes: [ControlHarnessAuthScope]
        var issuedAt: Date
        var expiresAt: Date
        var revokedAt: Date?
    }

    private let storageURL: URL
    private let configuration: Configuration
    private let now: @Sendable () -> Date

    private var pairingRecords: [String: PairingRecord] = [:]
    private var tokensByValue: [String: StoredToken] = [:]

    init(
        storageURL: URL,
        configuration: Configuration = .environment(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.storageURL = storageURL
        self.configuration = configuration
        self.now = now
        loadPersistedState()
    }

    func beginPairing(
        client: String?,
        requestedScopes: [String]?
    ) throws -> ControlHarnessPairingBeginResult {
        pruneExpiredState(referenceDate: now())

        let pairingCode = Self.makeTokenString()
        let normalizedClient = Self.normalizedClientName(client)
        let scopes = try Self.normalizeScopes(requestedScopes)
        let createdAt = now()
        let expiresAt = createdAt.addingTimeInterval(configuration.pairingCodeTTLSeconds)
        pairingRecords[pairingCode] = PairingRecord(
            pairingCode: pairingCode,
            client: normalizedClient,
            scopes: scopes,
            createdAt: createdAt,
            expiresAt: expiresAt
        )

        return ControlHarnessPairingBeginResult(
            pairingCode: pairingCode,
            client: normalizedClient,
            scopes: Self.sortedScopeStrings(scopes),
            expiresAt: Self.iso8601(expiresAt)
        )
    }

    func exchangePairingCode(_ pairingCode: String) throws -> ControlHarnessTokenIssueResult {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard let record = pairingRecords.removeValue(forKey: pairingCode) else {
            throw ControlHarnessAuthError.invalidPairingCode
        }
        guard record.expiresAt > currentTime else {
            throw ControlHarnessAuthError.expiredPairingCode
        }

        let issued = try issueToken(
            client: record.client,
            scopes: record.scopes,
            issuedAt: currentTime
        )
        try persist()
        return issued
    }

    func validate(
        token: String?,
        requiredScope: ControlHarnessAuthScope?
    ) -> Validation {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard let token, token.isEmpty == false else {
            return .deny(
                errorCode: "unauthorized",
                errorMessage: "A valid gateway auth token is required"
            )
        }
        guard let stored = tokensByValue[token] else {
            return .deny(
                errorCode: "unauthorized",
                errorMessage: "The gateway auth token is invalid, expired, or revoked"
            )
        }
        guard stored.revokedAt == nil, stored.expiresAt > currentTime else {
            tokensByValue.removeValue(forKey: token)
            try? persist()
            return .deny(
                errorCode: "unauthorized",
                errorMessage: "The gateway auth token is invalid, expired, or revoked"
            )
        }

        let scopes = Set(stored.scopes)
        if let requiredScope, scopes.contains(requiredScope) == false {
            return .deny(
                errorCode: "forbidden",
                errorMessage: "The gateway auth token does not allow \(requiredScope.rawValue) operations"
            )
        }

        return .allow(Grant(
            tokenID: stored.tokenID,
            client: stored.client,
            scopes: scopes,
            issuedAt: stored.issuedAt,
            expiresAt: stored.expiresAt
        ))
    }

    func rotate(token: String) throws -> ControlHarnessTokenIssueResult {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard let stored = tokensByValue[token] else {
            throw ControlHarnessAuthError.invalidToken
        }
        guard stored.revokedAt == nil, stored.expiresAt > currentTime else {
            tokensByValue.removeValue(forKey: token)
            try? persist()
            throw ControlHarnessAuthError.invalidToken
        }

        var revoked = stored
        revoked.revokedAt = currentTime
        tokensByValue[token] = revoked
        let issued = try issueToken(
            client: stored.client,
            scopes: Set(stored.scopes),
            issuedAt: currentTime
        )
        try persist()
        return issued
    }

    func revoke(token: String) throws -> ControlHarnessTokenStatusResult {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard var stored = tokensByValue[token] else {
            throw ControlHarnessAuthError.invalidToken
        }
        guard stored.revokedAt == nil, stored.expiresAt > currentTime else {
            tokensByValue.removeValue(forKey: token)
            try? persist()
            throw ControlHarnessAuthError.invalidToken
        }

        stored.revokedAt = currentTime
        tokensByValue[token] = stored
        try persist()
        return Self.tokenStatus(from: stored)
    }

    func tokenStatus(for token: String) throws -> ControlHarnessTokenStatusResult {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard let stored = tokensByValue[token] else {
            throw ControlHarnessAuthError.invalidToken
        }
        guard stored.expiresAt > currentTime else {
            tokensByValue.removeValue(forKey: token)
            try? persist()
            throw ControlHarnessAuthError.invalidToken
        }
        return Self.tokenStatus(from: stored)
    }

    private func issueToken(
        client: String,
        scopes: Set<ControlHarnessAuthScope>,
        issuedAt: Date
    ) throws -> ControlHarnessTokenIssueResult {
        let token = Self.makeTokenString()
        let tokenID = UUID().uuidString.lowercased()
        let expiresAt = issuedAt.addingTimeInterval(configuration.tokenTTLSeconds)
        let stored = StoredToken(
            token: token,
            tokenID: tokenID,
            client: client,
            scopes: Array(scopes).sorted(by: { $0.rawValue < $1.rawValue }),
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: nil
        )
        tokensByValue[token] = stored
        return ControlHarnessTokenIssueResult(
            token: token,
            tokenID: tokenID,
            client: client,
            scopes: Self.sortedScopeStrings(scopes),
            issuedAt: Self.iso8601(issuedAt),
            expiresAt: Self.iso8601(expiresAt)
        )
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        tokensByValue = Dictionary(uniqueKeysWithValues: state.tokens.map { ($0.token, $0) })
        pruneExpiredState(referenceDate: now())
    }

    private func persist() throws {
        pruneExpiredState(referenceDate: now())

        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let state = PersistedState(tokens: tokensByValue.values.sorted(by: { $0.tokenID < $1.tokenID }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: storageURL, options: .atomic)
    }

    private func pruneExpiredState(referenceDate: Date) {
        pairingRecords = pairingRecords.filter { _, record in
            record.expiresAt > referenceDate
        }
        tokensByValue = tokensByValue.filter { _, token in
            if token.expiresAt <= referenceDate {
                return false
            }
            if let revokedAt = token.revokedAt, revokedAt <= referenceDate {
                return false
            }
            return true
        }
    }

    private static func normalizedClientName(_ client: String?) -> String {
        let trimmed = client?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty == false {
            return trimmed
        }
        return "paired-client"
    }

    private static func normalizeScopes(_ requestedScopes: [String]?) throws -> Set<ControlHarnessAuthScope> {
        let requestedScopes = requestedScopes ?? [ControlHarnessAuthScope.observe.rawValue]
        let scopes = try Set(requestedScopes.map { rawScope in
            let normalized = rawScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let scope = ControlHarnessAuthScope(rawValue: normalized) else {
                throw ControlHarnessAuthError.invalidScope(rawScope)
            }
            return scope
        })

        guard scopes.isEmpty == false else {
            throw ControlHarnessAuthError.invalidScope("empty")
        }

        if scopes.contains(.mutate) {
            return scopes.union([.observe])
        }
        return scopes
    }

    private static func tokenStatus(from stored: StoredToken) -> ControlHarnessTokenStatusResult {
        ControlHarnessTokenStatusResult(
            tokenID: stored.tokenID,
            client: stored.client,
            scopes: sortedScopeStrings(Set(stored.scopes)),
            issuedAt: iso8601(stored.issuedAt),
            expiresAt: iso8601(stored.expiresAt),
            revokedAt: stored.revokedAt.map(iso8601)
        )
    }

    private static func sortedScopeStrings(_ scopes: Set<ControlHarnessAuthScope>) -> [String] {
        scopes.map(\.rawValue).sorted()
    }

    private static func makeTokenString() -> String {
        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(first)\(second)"
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum ControlHarnessAuthError: LocalizedError {
    case invalidPairingCode
    case expiredPairingCode
    case invalidScope(String)
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .invalidPairingCode:
            return "The pairing code is invalid"
        case .expiredPairingCode:
            return "The pairing code has expired"
        case .invalidScope(let scope):
            return "Unsupported auth scope: \(scope)"
        case .invalidToken:
            return "The gateway auth token is invalid, expired, or revoked"
        }
    }
}
