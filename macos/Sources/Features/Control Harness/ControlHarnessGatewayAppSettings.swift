import CryptoKit
import Foundation

struct ControlHarnessGatewayAppSettings: Equatable, Sendable {
    struct StorageScope: Equatable, Sendable {
        let namespaceKey: String

        static func current(
            bundle: Bundle = .main,
            processInfo: ProcessInfo = .processInfo
        ) -> Self {
            let bundleID = normalizedValue(bundle.bundleIdentifier) ?? "com.leongong.ghodex"
            let installPath = normalizedValue(
                bundle.bundleURL.resolvingSymlinksInPath().path
            ) ?? normalizedValue(
                bundle.executableURL?.resolvingSymlinksInPath().path
            ) ?? normalizedValue(
                processInfo.arguments.first
            ) ?? "unknown"

            let material = "\(bundleID)|\(installPath)"
            let digest = SHA256.hash(data: Data(material.utf8))
            let suffix = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
            return Self(namespaceKey: "ControlHarnessGateway.Scope.\(bundleID).\(suffix)")
        }
    }

    static let enabledKey = "ControlHarnessGateway.Enabled"
    static let listenHostKey = "ControlHarnessGateway.ListenHost"
    static let listenPortKey = "ControlHarnessGateway.ListenPort"
    static let pairingAdvertiseHostKey = "ControlHarnessGateway.PairingAdvertiseHost"
    static let showPairingQrOnLaunchKey = "ControlHarnessGateway.ShowPairingQrOnLaunch"
    static let semanticProfileKey = "ControlHarnessGateway.SemanticProfile"

    static let defaultEnabled = true
    static let defaultListenHost = "0.0.0.0"
    static let defaultListenPort: UInt16 = 9527
    static let defaultSemanticProfile = ControlHarnessSemanticProfile.defaultValue.rawValue

    var isEnabled = Self.defaultEnabled
    var listenHost = Self.defaultListenHost
    var listenPort = Self.defaultListenPort
    var pairingAdvertiseHost = ""
    var showPairingQrOnLaunch = false
    var semanticProfile = Self.defaultSemanticProfile

    var semanticProfileValue: ControlHarnessSemanticProfile {
        ControlHarnessSemanticProfile.parse(semanticProfile)
    }

    init(
        isEnabled: Bool = Self.defaultEnabled,
        listenHost: String = Self.defaultListenHost,
        listenPort: UInt16 = Self.defaultListenPort,
        pairingAdvertiseHost: String = "",
        showPairingQrOnLaunch: Bool = false,
        semanticProfile: String = Self.defaultSemanticProfile
    ) {
        self.isEnabled = isEnabled
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.pairingAdvertiseHost = pairingAdvertiseHost
        self.showPairingQrOnLaunch = showPairingQrOnLaunch
        self.semanticProfile = semanticProfile
    }

    func sanitized() -> Self {
        var copy = self
        let trimmedHost = copy.listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.listenHost = trimmedHost.isEmpty ? Self.defaultListenHost : trimmedHost

        if copy.listenPort == 0 {
            copy.listenPort = Self.defaultListenPort
        }

        copy.pairingAdvertiseHost = copy.pairingAdvertiseHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
        copy.semanticProfile = ControlHarnessSemanticProfile.parse(copy.semanticProfile).rawValue
        return copy
    }

    var normalizedPairingAdvertiseHost: String? {
        let trimmed = pairingAdvertiseHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseListenPort(_ rawValue: String) -> UInt16? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        guard trimmed.allSatisfy(\.isNumber) else { return nil }
        guard let parsedPort = UInt16(trimmed), parsedPort > 0 else { return nil }
        return parsedPort
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        scope: StorageScope = .current()
    ) -> Self {
        let resolvedScope = hasScopedValues(userDefaults: userDefaults, scope: scope) ? scope : nil

        var settings = Self()
        settings.isEnabled = userDefaults.object(forKey: storageKey(enabledKey, scope: resolvedScope)) == nil
            ? defaultEnabled
            : userDefaults.bool(forKey: storageKey(enabledKey, scope: resolvedScope))

        let storedHost = userDefaults.string(
            forKey: storageKey(listenHostKey, scope: resolvedScope)
        ) ?? defaultListenHost
        settings.listenHost = storedHost

        let storedPort = userDefaults.integer(
            forKey: storageKey(listenPortKey, scope: resolvedScope)
        )
        if storedPort >= 1 && storedPort <= 65_535 {
            settings.listenPort = UInt16(storedPort)
        } else {
            settings.listenPort = defaultListenPort
        }

        settings.pairingAdvertiseHost = userDefaults.string(
            forKey: storageKey(pairingAdvertiseHostKey, scope: resolvedScope)
        ) ?? ""
        settings.showPairingQrOnLaunch = userDefaults.bool(
            forKey: storageKey(showPairingQrOnLaunchKey, scope: resolvedScope)
        )
        settings.semanticProfile = userDefaults.string(
            forKey: storageKey(semanticProfileKey, scope: resolvedScope)
        ) ?? defaultSemanticProfile
        return settings.sanitized()
    }

    func save(
        userDefaults: UserDefaults = .standard,
        scope: StorageScope = .current()
    ) {
        let sanitized = sanitized()
        userDefaults.set(sanitized.isEnabled, forKey: Self.storageKey(Self.enabledKey, scope: scope))
        userDefaults.set(sanitized.listenHost, forKey: Self.storageKey(Self.listenHostKey, scope: scope))
        userDefaults.set(Int(sanitized.listenPort), forKey: Self.storageKey(Self.listenPortKey, scope: scope))
        userDefaults.set(
            sanitized.pairingAdvertiseHost,
            forKey: Self.storageKey(Self.pairingAdvertiseHostKey, scope: scope)
        )
        userDefaults.set(
            sanitized.showPairingQrOnLaunch,
            forKey: Self.storageKey(Self.showPairingQrOnLaunchKey, scope: scope)
        )
        userDefaults.set(
            sanitized.semanticProfile,
            forKey: Self.storageKey(Self.semanticProfileKey, scope: scope)
        )
    }

    func resolvedConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ControlHarnessGateway.Configuration {
        let sanitized = sanitized()
        var configuration = ControlHarnessGateway.Configuration.environment(environment)
        configuration.isEnabled = sanitized.isEnabled
        configuration.listenHost = sanitized.listenHost
        configuration.listenPort = sanitized.listenPort
        configuration.semanticProfile = sanitized.semanticProfileValue
        return configuration
    }

    private static func hasScopedValues(
        userDefaults: UserDefaults,
        scope: StorageScope
    ) -> Bool {
        trackedKeys.contains {
            userDefaults.object(forKey: storageKey($0, scope: scope)) != nil
        }
    }

    private static func storageKey(
        _ key: String,
        scope: StorageScope?
    ) -> String {
        guard let scope else { return key }
        return "\(scope.namespaceKey).\(key)"
    }

    private static let trackedKeys = [
        enabledKey,
        listenHostKey,
        listenPortKey,
        pairingAdvertiseHostKey,
        showPairingQrOnLaunchKey,
        semanticProfileKey,
    ]

    private static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
