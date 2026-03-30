import Foundation
import Testing
@testable import GhoDex

struct ControlHarnessGatewayAppSettingsTests {
    @Test func parseListenPortRejectsMixedAndOutOfRangeInput() {
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("29527") == 29527)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort(" 29527 ") == 29527)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("") == nil)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("0") == nil)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("12abc") == nil)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("95 27") == nil)
        #expect(ControlHarnessGatewayAppSettings.parseListenPort("65536") == nil)
    }

    @Test func settingsRoundTripWithinStorageScope() throws {
        let suiteName = "ghdx.tests.gateway-settings.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let scopeA = ControlHarnessGatewayAppSettings.StorageScope(namespaceKey: "scope-A")
        let scopeB = ControlHarnessGatewayAppSettings.StorageScope(namespaceKey: "scope-B")

        let saved = ControlHarnessGatewayAppSettings(
            isEnabled: true,
            listenHost: "192.168.3.145",
            listenPort: 29527,
            pairingAdvertiseHost: "desktop.local",
            showPairingQrOnLaunch: true,
            semanticProfile: ControlHarnessSemanticProfile.codex.rawValue
        )
        saved.save(userDefaults: userDefaults, scope: scopeA)

        let loadedA = ControlHarnessGatewayAppSettings.load(userDefaults: userDefaults, scope: scopeA)
        let loadedB = ControlHarnessGatewayAppSettings.load(userDefaults: userDefaults, scope: scopeB)

        #expect(loadedA == saved)
        #expect(loadedB == ControlHarnessGatewayAppSettings())
    }

    @Test func settingsLoadFallsBackToLegacyKeysWhenScopedValuesAreMissing() throws {
        let suiteName = "ghdx.tests.gateway-settings-legacy.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        userDefaults.set(false, forKey: ControlHarnessGatewayAppSettings.enabledKey)
        userDefaults.set("127.0.0.1", forKey: ControlHarnessGatewayAppSettings.listenHostKey)
        userDefaults.set(19527, forKey: ControlHarnessGatewayAppSettings.listenPortKey)
        userDefaults.set("legacy.local", forKey: ControlHarnessGatewayAppSettings.pairingAdvertiseHostKey)
        userDefaults.set(true, forKey: ControlHarnessGatewayAppSettings.showPairingQrOnLaunchKey)

        let loaded = ControlHarnessGatewayAppSettings.load(
            userDefaults: userDefaults,
            scope: .init(namespaceKey: "scoped")
        )

        #expect(loaded.isEnabled == false)
        #expect(loaded.listenHost == "127.0.0.1")
        #expect(loaded.listenPort == 19527)
        #expect(loaded.pairingAdvertiseHost == "legacy.local")
        #expect(loaded.showPairingQrOnLaunch == true)
        #expect(loaded.semanticProfile == ControlHarnessSemanticProfile.generic.rawValue)
    }

    @Test func resolvedConfigurationPrefersScopedSettingsOverEnvironment() {
        let settings = ControlHarnessGatewayAppSettings(
            isEnabled: true,
            listenHost: "0.0.0.0",
            listenPort: 29527,
            pairingAdvertiseHost: "",
            showPairingQrOnLaunch: false,
            semanticProfile: ControlHarnessSemanticProfile.claudeCode.rawValue
        )

        let configuration = settings.resolvedConfiguration(environment: [
            "GHODEX_CONTROL_HARNESS_GATEWAY_ENABLED": "false",
            "GHODEX_CONTROL_HARNESS_GATEWAY_HOST": "127.0.0.1",
            "GHODEX_CONTROL_HARNESS_GATEWAY_PORT": "9527",
        ])

        #expect(configuration.isEnabled == true)
        #expect(configuration.listenHost == "0.0.0.0")
        #expect(configuration.listenPort == 29527)
        #expect(configuration.semanticProfile == .claudeCode)
    }
}
