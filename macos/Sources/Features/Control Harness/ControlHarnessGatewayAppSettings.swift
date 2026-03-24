import Foundation

struct ControlHarnessGatewayAppSettings: Equatable, Sendable {
    static let enabledKey = "ControlHarnessGateway.Enabled"
    static let listenHostKey = "ControlHarnessGateway.ListenHost"
    static let listenPortKey = "ControlHarnessGateway.ListenPort"
    static let pairingAdvertiseHostKey = "ControlHarnessGateway.PairingAdvertiseHost"
    static let showPairingQrOnLaunchKey = "ControlHarnessGateway.ShowPairingQrOnLaunch"

    static let defaultEnabled = true
    static let defaultListenHost = "0.0.0.0"
    static let defaultListenPort: UInt16 = 9527

    var isEnabled = Self.defaultEnabled
    var listenHost = Self.defaultListenHost
    var listenPort = Self.defaultListenPort
    var pairingAdvertiseHost = ""
    var showPairingQrOnLaunch = false

    func sanitized() -> Self {
        var copy = self
        let trimmedHost = copy.listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.listenHost = trimmedHost.isEmpty ? Self.defaultListenHost : trimmedHost

        if copy.listenPort == 0 {
            copy.listenPort = Self.defaultListenPort
        }

        copy.pairingAdvertiseHost = copy.pairingAdvertiseHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    var normalizedPairingAdvertiseHost: String? {
        let trimmed = pairingAdvertiseHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func registerDefaults(userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            enabledKey: defaultEnabled,
            listenHostKey: defaultListenHost,
            listenPortKey: Int(defaultListenPort),
            pairingAdvertiseHostKey: "",
            showPairingQrOnLaunchKey: false,
        ])
    }

    static func load(userDefaults: UserDefaults = .standard) -> Self {
        registerDefaults(userDefaults: userDefaults)

        var settings = Self()
        settings.isEnabled = userDefaults.object(forKey: enabledKey) == nil
            ? defaultEnabled
            : userDefaults.bool(forKey: enabledKey)

        let storedHost = userDefaults.string(forKey: listenHostKey) ?? defaultListenHost
        settings.listenHost = storedHost

        let storedPort = userDefaults.integer(forKey: listenPortKey)
        if storedPort >= 1 && storedPort <= 65_535 {
            settings.listenPort = UInt16(storedPort)
        } else {
            settings.listenPort = defaultListenPort
        }

        settings.pairingAdvertiseHost = userDefaults.string(forKey: pairingAdvertiseHostKey) ?? ""
        settings.showPairingQrOnLaunch = userDefaults.bool(forKey: showPairingQrOnLaunchKey)
        return settings.sanitized()
    }

    func save(userDefaults: UserDefaults = .standard) {
        let sanitized = sanitized()
        userDefaults.set(sanitized.isEnabled, forKey: Self.enabledKey)
        userDefaults.set(sanitized.listenHost, forKey: Self.listenHostKey)
        userDefaults.set(Int(sanitized.listenPort), forKey: Self.listenPortKey)
        userDefaults.set(sanitized.pairingAdvertiseHost, forKey: Self.pairingAdvertiseHostKey)
        userDefaults.set(sanitized.showPairingQrOnLaunch, forKey: Self.showPairingQrOnLaunchKey)
    }

    func resolvedConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ControlHarnessGateway.Configuration {
        let sanitized = sanitized()
        var configuration = ControlHarnessGateway.Configuration.environment(environment)
        configuration.isEnabled = sanitized.isEnabled
        configuration.listenHost = sanitized.listenHost
        configuration.listenPort = sanitized.listenPort
        return configuration
    }
}
