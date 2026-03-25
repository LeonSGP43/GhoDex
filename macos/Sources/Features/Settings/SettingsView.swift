import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case gateway
    }

    // We need access to our app delegate to know if we're quitting or not.
    @EnvironmentObject private var appDelegate: AppDelegate
    @AppStorage(AppLanguageSetting.storageKey)
    private var selectedLanguageRawValue: String = AppLanguageSetting.storedSelection().rawValue
    @State private var selectedTab: SettingsTab = .general
    @State private var gatewayEnabled = false
    @State private var gatewayListenHost = ""
    @State private var gatewayPortText = ""
    @State private var gatewayPairingHost = ""
    @State private var gatewayShowQrOnLaunch = false

    private var selectedLanguage: Binding<AppLanguageSetting> {
        Binding(
            get: {
                AppLanguageSetting(rawValue: selectedLanguageRawValue) ?? .system
            },
            set: { newValue in
                selectedLanguageRawValue = newValue.rawValue
                newValue.apply()
            }
        )
    }

    private var needsRestart: Bool {
        (AppLanguageSetting(rawValue: selectedLanguageRawValue) ?? .system) != AppLanguageSetting.launchedSetting
    }

    private var gatewaySettingsDirty: Bool {
        let current = gatewayDraftSettings()
        return current != appDelegate.controlHarnessGatewaySettings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(L10n.Settings.generalTab, systemImage: "gearshape") }
                .tag(SettingsTab.general)

            gatewayTab
                .tabItem { Label(L10n.Settings.gatewayTab, systemImage: "network") }
                .tag(SettingsTab.gateway)
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear(perform: syncGatewayForm)
        .onReceive(appDelegate.$controlHarnessGatewaySettings) { _ in
            syncGatewayForm()
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.title)
                        .font(.title)
                    Text(L10n.Settings.body)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Settings.languageTitle)
                    .font(.headline)
                Picker(L10n.Settings.languageTitle, selection: selectedLanguage) {
                    ForEach(AppLanguageSetting.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(L10n.Settings.languageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsRestart {
                HStack {
                    Text(L10n.Settings.languageRestartRequired)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.Settings.restartNow) {
                        appDelegate.relaunchApplication()
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var gatewayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.Settings.gatewayTitle)
                    .font(.title2.weight(.semibold))

                Text(L10n.Settings.gatewayDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L10n.Settings.gatewayEnabled, isOn: $gatewayEnabled)
                Toggle(L10n.Settings.gatewayShowQrOnLaunch, isOn: $gatewayShowQrOnLaunch)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayListenHost)
                        .font(.headline)
                    TextField("0.0.0.0", text: $gatewayListenHost)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayListenHostHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayPort)
                        .font(.headline)
                    TextField("9527", text: $gatewayPortText)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayPortHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayPairingHost)
                        .font(.headline)
                    TextField(L10n.Settings.gatewayPairingHostPlaceholder, text: $gatewayPairingHost)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayPairingHostHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.Settings.gatewayStatus)
                        .font(.headline)
                    Text(appDelegate.controlHarnessGatewayStatusMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(L10n.Settings.gatewayApply) {
                        appDelegate.saveControlHarnessGatewaySettings(gatewayDraftSettings())
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.Settings.gatewayShowQr) {
                        appDelegate.saveControlHarnessGatewaySettings(gatewayDraftSettings())
                        appDelegate.showRemotePairingQRCode(nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!gatewayEnabled)
                }

                if gatewaySettingsDirty {
                    Text(L10n.Settings.gatewayPendingChanges)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func syncGatewayForm() {
        let settings = appDelegate.controlHarnessGatewaySettings
        gatewayEnabled = settings.isEnabled
        gatewayListenHost = settings.listenHost
        gatewayPortText = String(settings.listenPort)
        gatewayPairingHost = settings.pairingAdvertiseHost
        gatewayShowQrOnLaunch = settings.showPairingQrOnLaunch
    }

    private func gatewayDraftSettings() -> ControlHarnessGatewayAppSettings {
        let digits = gatewayPortText.filter(\.isNumber)
        let parsedPort = UInt16(digits) ?? ControlHarnessGatewayAppSettings.defaultListenPort
        return ControlHarnessGatewayAppSettings(
            isEnabled: gatewayEnabled,
            listenHost: gatewayListenHost,
            listenPort: parsedPort,
            pairingAdvertiseHost: gatewayPairingHost,
            showPairingQrOnLaunch: gatewayShowQrOnLaunch
        ).sanitized()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
