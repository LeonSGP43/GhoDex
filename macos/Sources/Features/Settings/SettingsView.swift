import AppKit
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: Hashable, CaseIterable {
        case general
        case appearance
        case gateway
    }

    @EnvironmentObject private var appDelegate: AppDelegate
    private let visibleTabs: [SettingsTab]
    private let externalSelection: Binding<SettingsTab>?
    private let onSelectedTabChange: ((SettingsTab) -> Void)?
    @AppStorage(AppLanguageSetting.storageKey)
    private var selectedLanguageRawValue: String = AppLanguageSetting.storedSelection().rawValue
    @State private var selectedTab: SettingsTab = .general
    @State private var gatewayEnabled = false
    @State private var gatewayListenHost = ""
    @State private var gatewayPortText = ""
    @State private var gatewayPairingHost = ""
    @State private var gatewayShowQrOnLaunch = false
    @State private var gatewaySemanticProfile: ControlHarnessSemanticProfile = .defaultValue
    @State private var builtInIconSelection: Ghostty.MacOSIcon = .official
    @State private var iconFeedbackMessage: String?
    @State private var iconFeedbackIsError = false

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
        gatewayDraftSettings() != appDelegate.controlHarnessGatewaySettings
    }

    private var gatewayPortValidationMessage: String? {
        ControlHarnessGatewayAppSettings.parseListenPort(gatewayPortText) == nil
            ? L10n.Settings.gatewayPortInvalid
            : nil
    }

    private var savedIconSettings: AppIconSettings {
        appDelegate.appIconSettings.sanitized
    }

    private var currentAppIconImage: NSImage {
        appDelegate.appIcon ?? savedIconSettings.previewImage(in: .main) ?? NSImage()
    }

    private var draftAppIconImage: NSImage {
        AppIconSettings(icon: builtInIconSelection).previewImage(in: .main) ?? currentAppIconImage
    }

    init(
        initialTab: SettingsTab = .general,
        visibleTabs: [SettingsTab] = SettingsTab.allCases,
        selection: Binding<SettingsTab>? = nil,
        onSelectedTabChange: ((SettingsTab) -> Void)? = nil
    ) {
        let normalizedTabs = visibleTabs.isEmpty ? SettingsTab.allCases : visibleTabs
        self.visibleTabs = normalizedTabs
        self.externalSelection = selection
        self.onSelectedTabChange = onSelectedTabChange
        let resolvedInitialTab = normalizedTabs.contains(initialTab) ? initialTab : normalizedTabs[0]
        _selectedTab = State(initialValue: selection?.wrappedValue ?? resolvedInitialTab)
    }

    var body: some View {
        Group {
            if visibleTabs.count == 1, let onlyTab = visibleTabs.first {
                content(for: onlyTab)
            } else {
                TabView(selection: selectedTabBinding) {
                    if visibleTabs.contains(.general) {
                        generalTab
                            .tabItem { Label(L10n.Settings.generalTab, systemImage: "gearshape") }
                            .tag(SettingsTab.general)
                    }

                    if visibleTabs.contains(.appearance) {
                        appearanceTab
                            .tabItem { Label(L10n.Settings.appearanceTab, systemImage: "app.badge") }
                            .tag(SettingsTab.appearance)
                    }

                    if visibleTabs.contains(.gateway) {
                        gatewayTab
                            .tabItem { Label(L10n.Settings.gatewayTab, systemImage: "network") }
                            .tag(SettingsTab.gateway)
                    }
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            syncGatewayForm()
            syncIconForm(clearFeedback: true)
            onSelectedTabChange?(selectedTabBinding.wrappedValue)
        }
        .onReceive(appDelegate.$controlHarnessGatewaySettings) { _ in
            syncGatewayForm()
        }
        .onReceive(appDelegate.$appIconSettings) { _ in
            syncIconForm(clearFeedback: false)
        }
        .onChange(of: builtInIconSelection) { _ in
            saveIconSettingsIfNeeded()
        }
        .onChange(of: selectedTabBinding.wrappedValue) { newValue in
            onSelectedTabChange?(newValue)
        }
    }

    private var selectedTabBinding: Binding<SettingsTab> {
        externalSelection ?? $selectedTab
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            generalTab
        case .appearance:
            appearanceTab
        case .gateway:
            gatewayTab
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: currentAppIconImage)
                        .resizable()
                        .interpolation(.high)
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

                Divider()

                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: currentAppIconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Settings.iconQuickTitle)
                            .font(.headline)
                        Text(L10n.Settings.iconQuickDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(L10n.Settings.iconOpenEditor) {
                        selectedTabBinding.wrappedValue = .appearance
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.Settings.iconTitle)
                    .font(.title2.weight(.semibold))

                Text(L10n.Settings.iconDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    HStack(alignment: .center, spacing: 18) {
                        Image(nsImage: draftAppIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 88, height: 88)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.Settings.iconPreview)
                                .font(.headline)
                            Text(L10n.Settings.iconLiveApply)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                builtInIconSection

                if let iconFeedbackMessage {
                    Text(iconFeedbackMessage)
                        .font(.caption)
                        .foregroundStyle(iconFeedbackIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var builtInIconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.iconBuiltInTitle)
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(Ghostty.MacOSIcon.builtInOptions, id: \.self) { icon in
                    Button {
                        builtInIconSelection = icon
                    } label: {
                        VStack(spacing: 10) {
                            Image(nsImage: builtInPreviewImage(for: icon))
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 56, height: 56)

                            Text(iconDisplayName(icon))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    builtInIconSelection == icon ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3),
                                    lineWidth: builtInIconSelection == icon ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                    if let gatewayPortValidationMessage {
                        Text(gatewayPortValidationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewaySemanticProfile)
                        .font(.headline)
                    Picker(L10n.Settings.gatewaySemanticProfile, selection: $gatewaySemanticProfile) {
                        Text(L10n.Settings.gatewaySemanticProfileGeneric).tag(ControlHarnessSemanticProfile.generic)
                        Text(L10n.Settings.gatewaySemanticProfileCodex).tag(ControlHarnessSemanticProfile.codex)
                        Text(L10n.Settings.gatewaySemanticProfileClaudeCode).tag(ControlHarnessSemanticProfile.claudeCode)
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.Settings.gatewaySemanticProfileHelp)
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
                    .disabled(gatewayPortValidationMessage != nil)

                    Button(L10n.Settings.gatewayShowQr) {
                        appDelegate.saveControlHarnessGatewaySettings(gatewayDraftSettings())
                        appDelegate.showRemotePairingQRCode(nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!gatewayEnabled || gatewayPortValidationMessage != nil)
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
        gatewaySemanticProfile = settings.semanticProfileValue
    }

    private func syncIconForm(clearFeedback: Bool) {
        let settings = savedIconSettings
        builtInIconSelection = settings.icon

        if clearFeedback {
            iconFeedbackMessage = nil
            iconFeedbackIsError = false
        }
    }

    private func iconDraftSettings() -> AppIconSettings {
        AppIconSettings(icon: builtInIconSelection).sanitized
    }

    private func builtInPreviewImage(for icon: Ghostty.MacOSIcon) -> NSImage {
        AppIconSettings(icon: icon).previewImage(in: .main) ?? currentAppIconImage
    }

    private func iconDisplayName(_ icon: Ghostty.MacOSIcon) -> String {
        switch icon {
        case .official:
            return L10n.Settings.iconOptionOfficial
        case .ghodex:
            return L10n.Settings.iconOptionGhodex
        case .banana:
            return L10n.Settings.iconOptionBanana
        case .blueprint:
            return L10n.Settings.iconOptionBlueprint
        case .chalkboard:
            return L10n.Settings.iconOptionChalkboard
        case .glass:
            return L10n.Settings.iconOptionGlass
        case .holographic:
            return L10n.Settings.iconOptionHolographic
        case .microchip:
            return L10n.Settings.iconOptionMicrochip
        case .paper:
            return L10n.Settings.iconOptionPaper
        case .retro:
            return L10n.Settings.iconOptionRetro
        case .xray:
            return L10n.Settings.iconOptionXray
        case .custom, .customStyle:
            return L10n.Settings.iconOptionOfficial
        }
    }

    private func saveIconSettings() {
        do {
            try appDelegate.saveVisualAppIconSettings(iconDraftSettings())
            iconFeedbackMessage = L10n.Settings.iconSaved
            iconFeedbackIsError = false
        } catch {
            iconFeedbackMessage = error.localizedDescription
            iconFeedbackIsError = true
        }
    }

    private func saveIconSettingsIfNeeded() {
        guard iconDraftSettings() != savedIconSettings else { return }
        saveIconSettings()
    }

    private func gatewayDraftSettings() -> ControlHarnessGatewayAppSettings {
        let parsedPort = ControlHarnessGatewayAppSettings.parseListenPort(gatewayPortText)
            ?? ControlHarnessGatewayAppSettings.defaultListenPort
        return ControlHarnessGatewayAppSettings(
            isEnabled: gatewayEnabled,
            listenHost: gatewayListenHost,
            listenPort: parsedPort,
            pairingAdvertiseHost: gatewayPairingHost,
            showPairingQrOnLaunch: gatewayShowQrOnLaunch,
            semanticProfile: gatewaySemanticProfile.rawValue
        ).sanitized()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
