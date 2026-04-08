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
    let desktopID: String
    let desktopLabel: String
    let preferredDesktopID: String
    let transportMode: String
    let publicEndpoint: String?
    let transportSharedSecret: String?
    let issuedAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case tokenID = "token_id"
        case client
        case scopes
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case preferredDesktopID = "preferred_desktop_id"
        case transportMode = "transport_mode"
        case publicEndpoint = "public_endpoint"
        case transportSharedSecret = "transport_shared_secret"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
    }
}

struct ControlHarnessTokenStatusResult: Encodable, Sendable {
    let tokenID: String
    let client: String
    let scopes: [String]
    let desktopID: String
    let desktopLabel: String
    let preferredDesktopID: String
    let transportMode: String
    let issuedAt: String
    let expiresAt: String
    let revokedAt: String?

    enum CodingKeys: String, CodingKey {
        case tokenID = "token_id"
        case client
        case scopes
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case preferredDesktopID = "preferred_desktop_id"
        case transportMode = "transport_mode"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }
}

struct ControlHarnessRegisteredDeviceResult: Sendable {
    let deviceID: String
    let displayLabel: String
    let trustState: String
    let lastSeenAt: String?
    let transportMode: String
    let capabilityFlags: [String]
}

struct ControlHarnessDesktopIdentityResult: Sendable {
    let desktopID: String
    let desktopLabel: String
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
        let subjectID: String
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
        let subjectID: String
        let pairingCode: String
        let client: String
        let deviceLabel: String
        let scopes: Set<ControlHarnessAuthScope>
        let createdAt: Date
        let expiresAt: Date
    }

    private struct PersistedState: Codable {
        var desktopIdentity: StoredDesktopIdentity?
        var tokens: [StoredToken]
        var devices: [StoredDevice]?
    }

    private struct StoredDesktopIdentity: Codable, Sendable {
        var desktopID: String
        var desktopLabel: String
    }

    private struct StoredToken: Codable, Sendable {
        var subjectID: String
        var token: String
        var tokenID: String
        var client: String
        var transportSharedSecret: String
        var scopes: [ControlHarnessAuthScope]
        var issuedAt: Date
        var expiresAt: Date
        var revokedAt: Date?

        enum CodingKeys: String, CodingKey {
            case subjectID
            case token
            case tokenID
            case client
            case transportSharedSecret
            case scopes
            case issuedAt
            case expiresAt
            case revokedAt
        }

        init(
            subjectID: String,
            token: String,
            tokenID: String,
            client: String,
            transportSharedSecret: String,
            scopes: [ControlHarnessAuthScope],
            issuedAt: Date,
            expiresAt: Date,
            revokedAt: Date?
        ) {
            self.subjectID = subjectID
            self.token = token
            self.tokenID = tokenID
            self.client = client
            self.transportSharedSecret = transportSharedSecret
            self.scopes = scopes
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
            self.revokedAt = revokedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            subjectID = try container.decode(String.self, forKey: .subjectID)
            token = try container.decode(String.self, forKey: .token)
            tokenID = try container.decode(String.self, forKey: .tokenID)
            client = try container.decode(String.self, forKey: .client)
            transportSharedSecret = try container.decodeIfPresent(String.self, forKey: .transportSharedSecret)
                ?? ControlHarnessGatewaySecureChannel.makeTransportSharedSecret()
            scopes = try container.decode([ControlHarnessAuthScope].self, forKey: .scopes)
            issuedAt = try container.decode(Date.self, forKey: .issuedAt)
            expiresAt = try container.decode(Date.self, forKey: .expiresAt)
            revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
        }
    }

    private enum StoredDeviceTrustState: String, Codable, Sendable {
        case trusted
        case revoked
    }

    private struct StoredDevice: Codable, Sendable {
        var deviceID: String
        var displayLabel: String
        var trustState: StoredDeviceTrustState
        var lastSeenAt: Date?
        var transportMode: String
        var capabilityFlags: [String]
    }

    private let storageURL: URL
    private let configuration: Configuration
    private let now: @Sendable () -> Date

    private var pairingRecords: [String: PairingRecord] = [:]
    private var tokensByValue: [String: StoredToken] = [:]
    private var desktopIdentity: StoredDesktopIdentity
    private var devicesByID: [String: StoredDevice] = [:]

    init(
        storageURL: URL,
        configuration: Configuration = .environment(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storageURL = storageURL
        self.configuration = configuration
        self.now = now
        let persistedState = Self.loadPersistedState(from: storageURL)
        if let restoredIdentity = persistedState?.desktopIdentity,
           restoredIdentity.desktopID.isEmpty == false,
           restoredIdentity.desktopLabel.isEmpty == false {
            self.desktopIdentity = restoredIdentity
        } else {
            self.desktopIdentity = Self.makeDefaultDesktopIdentity()
        }
        let restoredTokensByValue = Dictionary(
            uniqueKeysWithValues: (persistedState?.tokens ?? []).map { ($0.token, $0) }
        )
        let restoredDevicesByID = Dictionary(
            uniqueKeysWithValues: (persistedState?.devices ?? []).map { ($0.deviceID, $0) }
        )
        let referenceDate = now()
        self.pairingRecords = [:]
        self.tokensByValue = Self.prunedTokens(
            from: restoredTokensByValue,
            referenceDate: referenceDate
        )
        self.devicesByID = Self.backfilledDevices(
            from: self.tokensByValue,
            existingDevices: restoredDevicesByID
        )
    }

    func beginPairing(
        client: String?,
        requestedScopes: [String]?,
        deviceID: String? = nil,
        deviceLabel: String? = nil
    ) throws -> ControlHarnessPairingBeginResult {
        pruneExpiredState(referenceDate: now())

        let pairingCode = Self.makeTokenString()
        let normalizedClient = Self.normalizedClientName(client)
        let normalizedDeviceID = Self.normalizedDeviceID(deviceID) ?? UUID().uuidString.lowercased()
        let normalizedDeviceLabel = Self.normalizedDeviceLabel(deviceLabel) ?? normalizedClient
        let scopes = try Self.normalizeScopes(requestedScopes)
        let createdAt = now()
        let expiresAt = createdAt.addingTimeInterval(configuration.pairingCodeTTLSeconds)
        pairingRecords[pairingCode] = PairingRecord(
            subjectID: normalizedDeviceID,
            pairingCode: pairingCode,
            client: normalizedClient,
            deviceLabel: normalizedDeviceLabel,
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
        let record = pairingRecords.removeValue(forKey: pairingCode)
        pruneExpiredState(referenceDate: currentTime)

        guard let record else {
            throw ControlHarnessAuthError.invalidPairingCode
        }
        guard record.expiresAt > currentTime else {
            throw ControlHarnessAuthError.expiredPairingCode
        }

        let issued = try issueToken(
            subjectID: record.subjectID,
            client: record.client,
            scopes: record.scopes,
            issuedAt: currentTime,
            deviceDisplayLabel: record.deviceLabel
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
        if devicesByID[stored.subjectID]?.trustState == .revoked {
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
            subjectID: stored.subjectID,
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
            subjectID: stored.subjectID,
            client: stored.client,
            scopes: Set(stored.scopes),
            issuedAt: currentTime,
            deviceDisplayLabel: devicesByID[stored.subjectID]?.displayLabel ?? stored.client
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
        return tokenStatus(from: stored)
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
        return tokenStatus(from: stored)
    }

    func transportSharedSecret(for token: String) throws -> String {
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
        return stored.transportSharedSecret
    }

    func listDevices() -> [ControlHarnessRegisteredDeviceResult] {
        pruneExpiredState(referenceDate: now())
        return devicesByID.values
            .sorted(by: { lhs, rhs in
                if lhs.displayLabel == rhs.displayLabel {
                    return lhs.deviceID < rhs.deviceID
                }
                return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
            })
            .map(Self.registeredDeviceResult(from:))
    }

    func desktopIdentityResult() -> ControlHarnessDesktopIdentityResult {
        ControlHarnessDesktopIdentityResult(
            desktopID: desktopIdentity.desktopID,
            desktopLabel: desktopIdentity.desktopLabel
        )
    }

    func revokeDevice(deviceID: String) throws -> ControlHarnessRegisteredDeviceResult {
        guard let normalizedDeviceID = Self.normalizedDeviceID(deviceID),
              var device = devicesByID[normalizedDeviceID] else {
            throw ControlHarnessAuthError.deviceNotFound
        }

        let currentTime = now()
        device.trustState = .revoked
        devicesByID[normalizedDeviceID] = device

        for (tokenValue, var token) in tokensByValue where token.subjectID == normalizedDeviceID && token.revokedAt == nil {
            token.revokedAt = currentTime
            tokensByValue[tokenValue] = token
        }

        try persist()
        return Self.registeredDeviceResult(from: device)
    }

    func recordDeviceActivity(token: String, transportMode: String?) throws {
        let currentTime = now()
        pruneExpiredState(referenceDate: currentTime)

        guard let stored = tokensByValue[token],
              stored.revokedAt == nil,
              stored.expiresAt > currentTime else {
            throw ControlHarnessAuthError.invalidToken
        }

        ensureDeviceExists(
            deviceID: stored.subjectID,
            displayLabel: devicesByID[stored.subjectID]?.displayLabel ?? stored.client,
            trustState: .trusted,
            lastSeenAt: currentTime,
            transportMode: Self.sanitizeTransportMode(transportMode),
            capabilityFlags: devicesByID[stored.subjectID]?.capabilityFlags ?? []
        )
        try persist()
    }

    private func issueToken(
        subjectID: String,
        client: String,
        scopes: Set<ControlHarnessAuthScope>,
        issuedAt: Date,
        deviceDisplayLabel: String
    ) throws -> ControlHarnessTokenIssueResult {
        let token = Self.makeTokenString()
        let tokenID = UUID().uuidString.lowercased()
        let expiresAt = issuedAt.addingTimeInterval(configuration.tokenTTLSeconds)
        let transportSharedSecret = try ControlHarnessGatewaySecureChannel.makeTransportSharedSecret()
        ensureDeviceExists(
            deviceID: subjectID,
            displayLabel: deviceDisplayLabel,
            trustState: .trusted,
            lastSeenAt: issuedAt,
            transportMode: "lan",
            capabilityFlags: devicesByID[subjectID]?.capabilityFlags ?? []
        )
        let stored = StoredToken(
            subjectID: subjectID,
            token: token,
            tokenID: tokenID,
            client: client,
            transportSharedSecret: transportSharedSecret,
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
            desktopID: desktopIdentity.desktopID,
            desktopLabel: desktopIdentity.desktopLabel,
            preferredDesktopID: desktopIdentity.desktopID,
            transportMode: "lan",
            publicEndpoint: nil,
            transportSharedSecret: transportSharedSecret,
            issuedAt: Self.iso8601(issuedAt),
            expiresAt: Self.iso8601(expiresAt)
        )
    }

    private static func loadPersistedState(from storageURL: URL) -> PersistedState? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persist() throws {
        pruneExpiredState(referenceDate: now())

        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let state = PersistedState(
            desktopIdentity: desktopIdentity,
            tokens: tokensByValue.values.sorted(by: { $0.tokenID < $1.tokenID }),
            devices: devicesByID.values.sorted(by: { $0.deviceID < $1.deviceID })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: storageURL, options: .atomic)
    }

    private func pruneExpiredState(referenceDate: Date) {
        pairingRecords = pairingRecords.filter { _, record in
            record.expiresAt > referenceDate
        }
        tokensByValue = Self.prunedTokens(from: tokensByValue, referenceDate: referenceDate)
        backfillDevicesFromTokens()
    }

    private static func normalizedClientName(_ client: String?) -> String {
        let trimmed = client?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty == false {
            return trimmed
        }
        return "paired-client"
    }

    private static func normalizedDeviceID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedDeviceLabel(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func tokenStatus(from stored: StoredToken) -> ControlHarnessTokenStatusResult {
        ControlHarnessTokenStatusResult(
            tokenID: stored.tokenID,
            client: stored.client,
            scopes: Self.sortedScopeStrings(Set(stored.scopes)),
            desktopID: desktopIdentity.desktopID,
            desktopLabel: desktopIdentity.desktopLabel,
            preferredDesktopID: desktopIdentity.desktopID,
            transportMode: "lan",
            issuedAt: Self.iso8601(stored.issuedAt),
            expiresAt: Self.iso8601(stored.expiresAt),
            revokedAt: stored.revokedAt.map(Self.iso8601)
        )
    }

    private func ensureDeviceExists(
        deviceID: String,
        displayLabel: String,
        trustState: StoredDeviceTrustState,
        lastSeenAt: Date?,
        transportMode: String,
        capabilityFlags: [String]
    ) {
        let existing = devicesByID[deviceID]
        let normalizedLabel = Self.normalizedDeviceLabel(displayLabel) ?? existing?.displayLabel ?? "Unknown device"
        devicesByID[deviceID] = StoredDevice(
            deviceID: deviceID,
            displayLabel: normalizedLabel,
            trustState: trustState,
            lastSeenAt: lastSeenAt ?? existing?.lastSeenAt,
            transportMode: Self.sanitizeTransportMode(transportMode),
            capabilityFlags: capabilityFlags
        )
    }

    private func backfillDevicesFromTokens() {
        devicesByID = Self.backfilledDevices(from: tokensByValue, existingDevices: devicesByID)
    }

    private static func prunedTokens(
        from tokensByValue: [String: StoredToken],
        referenceDate: Date
    ) -> [String: StoredToken] {
        tokensByValue.filter { _, token in
            if token.expiresAt <= referenceDate {
                return false
            }
            if let revokedAt = token.revokedAt, revokedAt <= referenceDate {
                return false
            }
            return true
        }
    }

    private static func backfilledDevices(
        from tokensByValue: [String: StoredToken],
        existingDevices: [String: StoredDevice]
    ) -> [String: StoredDevice] {
        var devicesByID = existingDevices
        for token in tokensByValue.values {
            let existing = devicesByID[token.subjectID]
            let normalizedLabel = Self.normalizedDeviceLabel(
                existing?.displayLabel ?? token.client
            ) ?? "Unknown device"
            devicesByID[token.subjectID] = StoredDevice(
                deviceID: token.subjectID,
                displayLabel: normalizedLabel,
                trustState: existing?.trustState ?? .trusted,
                lastSeenAt: existing?.lastSeenAt ?? token.issuedAt,
                transportMode: Self.sanitizeTransportMode(existing?.transportMode),
                capabilityFlags: existing?.capabilityFlags ?? []
            )
        }
        return devicesByID
    }

    private static func sortedScopeStrings(_ scopes: Set<ControlHarnessAuthScope>) -> [String] {
        scopes.map(\.rawValue).sorted()
    }

    private static func makeTokenString() -> String {
        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(first)\(second)"
    }

    private static func makeDefaultDesktopIdentity() -> StoredDesktopIdentity {
        let desktopLabel = Host.current().localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = (desktopLabel?.isEmpty == false ? desktopLabel! : ProcessInfo.processInfo.hostName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return StoredDesktopIdentity(
            desktopID: UUID().uuidString.lowercased(),
            desktopLabel: resolvedLabel.isEmpty ? "GhoDex Desktop" : resolvedLabel
        )
    }

    private static func sanitizeTransportMode(_ rawValue: String?) -> String {
        rawValue == "relay" ? "relay" : "lan"
    }

    private static func registeredDeviceResult(from stored: StoredDevice) -> ControlHarnessRegisteredDeviceResult {
        ControlHarnessRegisteredDeviceResult(
            deviceID: stored.deviceID,
            displayLabel: stored.displayLabel,
            trustState: stored.trustState.rawValue,
            lastSeenAt: stored.lastSeenAt.map(Self.iso8601),
            transportMode: sanitizeTransportMode(stored.transportMode),
            capabilityFlags: stored.capabilityFlags
        )
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
    case deviceNotFound

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
        case .deviceNotFound:
            return "The requested device is not registered"
        }
    }
}
