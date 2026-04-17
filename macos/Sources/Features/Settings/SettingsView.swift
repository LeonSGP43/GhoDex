import AppKit
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: Hashable, CaseIterable {
        case general
        case appearance
        case gateway
    }

    private enum InputFeedbackScope {
        case mouseNavigation
        case splitPicker
    }

    @Environment(\.colorScheme) private var colorScheme
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
    @State private var mouseBackForwardSwitchesTabs = false
    @State private var splitPickerEnabled = false
    @State private var builtInIconSelection: Ghostty.MacOSIcon = .official
    @State private var inputFeedbackMessage: String?
    @State private var inputFeedbackIsError = false
    @State private var inputFeedbackScope: InputFeedbackScope?
    @State private var permissionsFeedbackMessage: String?
    @State private var iconFeedbackMessage: String?
    @State private var iconFeedbackIsError = false

    private var panelAccent: Color { GhoDexPanelPalette.accent }
    private var panelAccentStrong: Color { GhoDexPanelPalette.accentStrong }
    private var panelAccentSoft: Color { GhoDexPanelPalette.accentSoft }

    private let sidebarWidth: CGFloat = 248
    private let heroMetricMinWidth: CGFloat = 152
    private let iconColumns = [GridItem(.adaptive(minimum: 126), spacing: 14)]

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

    private var selectedPageTitle: String {
        title(for: selectedTabBinding.wrappedValue)
    }

    private var selectedPageSubtitle: String {
        subtitle(for: selectedTabBinding.wrappedValue)
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
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            if visibleTabs.count == 1, let onlyTab = visibleTabs.first {
                detailSurface(for: onlyTab)
                    .padding(20)
            } else {
                HStack(spacing: 18) {
                    settingsSidebar

                    detailSurface(for: selectedTabBinding.wrappedValue)
                }
                .padding(18)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .tint(panelAccent)
        .onAppear {
            syncGatewayForm()
            syncInputForm(clearFeedback: true)
            syncIconForm(clearFeedback: true)
            onSelectedTabChange?(selectedTabBinding.wrappedValue)
        }
        .onReceive(appDelegate.$controlHarnessGatewaySettings) { _ in
            syncGatewayForm()
        }
        .onReceive(appDelegate.$mouseBackForwardSwitchesTabs) { _ in
            syncInputForm(clearFeedback: false)
        }
        .onReceive(appDelegate.$splitPickerEnabled) { _ in
            syncInputForm(clearFeedback: false)
        }
        .onReceive(appDelegate.$appIconSettings) { _ in
            syncIconForm(clearFeedback: false)
        }
        .onChange(of: mouseBackForwardSwitchesTabs) { _ in
            saveMouseNavigationSettingIfNeeded()
        }
        .onChange(of: splitPickerEnabled) { _ in
            saveSplitPickerSettingIfNeeded()
        }
        .onChange(of: builtInIconSelection) { _ in
            saveIconSettingsIfNeeded()
        }
        .onChange(of: selectedTabBinding.wrappedValue) { newValue in
            onSelectedTabChange?(newValue)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.09, green: 0.10, blue: 0.12),
                    Color(red: 0.12, green: 0.13, blue: 0.16),
                    panelAccentStrong.opacity(0.18),
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                ]
                : [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.97, green: 0.96, blue: 0.94),
                    Color(red: 0.93, green: 0.95, blue: 0.98),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(panelAccentStrong.opacity(colorScheme == .dark ? 0.3 : 0.14))

                        Image(nsImage: currentAppIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(10)
                    }
                    .frame(width: 68, height: 68)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Settings.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(L10n.Settings.sidebarEyebrow)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(panelAccent)
                        Text(selectedPageTitle)
                            .font(.headline)
                    }
                }

                Text(L10n.Settings.sidebarDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleTabs, id: \.self) { tab in
                    sidebarTabButton(for: tab)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Settings.sidebarOverview)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                overviewPill(
                    icon: "globe",
                    title: selectedLanguage.wrappedValue.displayName,
                    detail: L10n.Settings.languageTitle
                )

                overviewPill(
                    icon: "app.badge",
                    title: iconDisplayName(savedIconSettings.icon),
                    detail: L10n.Settings.iconQuickTitle
                )

                overviewPill(
                    icon: gatewayEnabled ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    title: gatewayEnabled ? L10n.Settings.sidebarGatewayOn : L10n.Settings.sidebarGatewayOff,
                    detail: appDelegate.controlHarnessGatewayStatusMessage
                )
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedPageTitle)
                    .font(.headline)
                Text(selectedPageSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(panelAccent.opacity(colorScheme == .dark ? 0.16 : 0.1))
            )
        }
        .padding(20)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
        .overlay(roundedBorder(cornerRadius: 28))
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.15, green: 0.16, blue: 0.19),
                            Color(red: 0.11, green: 0.12, blue: 0.14),
                        ]
                        : [
                            Color(red: 0.99, green: 0.99, blue: 0.98),
                            Color(red: 0.95, green: 0.96, blue: 0.97),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.34),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func sidebarTabButton(for tab: SettingsTab) -> some View {
        let isSelected = selectedTabBinding.wrappedValue == tab

        return Button {
            selectedTabBinding.wrappedValue = tab
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28) : Color.clear)

                    Image(systemName: iconName(for: tab))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? panelAccent : Color.secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: tab))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(sidebarSubtitle(for: tab))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? panelAccent.opacity(colorScheme == .dark ? 0.18 : 0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? panelAccent.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .buttonStyle(.plain)
    }

    private func overviewPill(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(panelAccent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.65 : 0.75))
        )
    }

    private func detailSurface(for tab: SettingsTab) -> some View {
        content(for: tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(detailBackground)
            .overlay(roundedBorder(cornerRadius: 30))
    }

    private var detailBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.17, green: 0.18, blue: 0.21),
                            Color(red: 0.12, green: 0.13, blue: 0.15),
                        ]
                        : [
                            Color(red: 0.995, green: 0.995, blue: 0.99),
                            Color(red: 0.96, green: 0.965, blue: 0.972),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.42),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 28, y: 10)
    }

    private func roundedBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.24 : 0.1), lineWidth: 1)
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
        pageScroll {
            settingsHero(
                eyebrow: L10n.Settings.heroWorkspace,
                title: L10n.Settings.title,
                subtitle: L10n.Settings.body,
                accessory: AnyView(
                    heroMetrics {
                        heroMetric(
                            value: selectedLanguage.wrappedValue.displayName,
                            label: L10n.Settings.languageTitle,
                            systemImage: "globe"
                        )
                        heroMetric(
                            value: mouseBackForwardSwitchesTabs
                                ? L10n.Settings.mouseNavigationEnabledState
                                : L10n.Settings.mouseNavigationDisabledState,
                            label: L10n.Settings.mouseNavigationTitle,
                            systemImage: "computermouse"
                        )
                        heroMetric(
                            value: splitPickerEnabled
                                ? L10n.Settings.splitPickerEnabledState
                                : L10n.Settings.splitPickerDisabledState,
                            label: L10n.Settings.splitPickerTitle,
                            systemImage: "square.split.2x1"
                        )
                    }
                )
            )

            settingsSplitCard(
                title: L10n.Settings.languageTitle,
                subtitle: L10n.Settings.languageDescription,
                icon: "globe.americas"
            ) {
                Picker(L10n.Settings.languageTitle, selection: selectedLanguage) {
                    ForEach(AppLanguageSetting.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if needsRestart {
                    statusBanner(
                        text: L10n.Settings.languageRestartRequired,
                        tone: .warning,
                        actionTitle: L10n.Settings.restartNow
                    ) {
                        appDelegate.relaunchApplication()
                    }
                }
            }

            settingsSplitCard(
                title: L10n.Settings.mouseNavigationTitle,
                subtitle: L10n.Settings.mouseNavigationDescription,
                icon: "computermouse"
            ) {
                Toggle(L10n.Settings.mouseNavigationSwitchTabs, isOn: $mouseBackForwardSwitchesTabs)

                if let inputFeedbackMessage, inputFeedbackScope == .mouseNavigation {
                    statusBanner(
                        text: inputFeedbackMessage,
                        tone: inputFeedbackIsError ? .danger : .success
                    )
                }
            }

            settingsSplitCard(
                title: L10n.Settings.splitPickerTitle,
                subtitle: L10n.Settings.splitPickerDescription,
                icon: "square.split.2x1"
            ) {
                Toggle(L10n.Settings.splitPickerToggle, isOn: $splitPickerEnabled)

                Text(L10n.Settings.splitPickerFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let inputFeedbackMessage, inputFeedbackScope == .splitPicker {
                    statusBanner(
                        text: inputFeedbackMessage,
                        tone: inputFeedbackIsError ? .danger : .success
                    )
                }
            }

            settingsSplitCard(
                title: L10n.Settings.permissionsTitle,
                subtitle: L10n.Settings.permissionsDescription,
                icon: "lock.shield"
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Button(L10n.Settings.permissionsOpenFilesAndFolders) {
                            openPrivacySettings(.filesAndFolders)
                        }

                        Button(L10n.Settings.permissionsOpenFullDiskAccess) {
                            openPrivacySettings(.fullDiskAccess)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(L10n.Settings.permissionsOpenFilesAndFolders) {
                            openPrivacySettings(.filesAndFolders)
                        }

                        Button(L10n.Settings.permissionsOpenFullDiskAccess) {
                            openPrivacySettings(.fullDiskAccess)
                        }
                    }
                }

                if let permissionsFeedbackMessage {
                    statusBanner(text: permissionsFeedbackMessage, tone: .danger)
                }
            }

            settingsCard(
                title: L10n.Settings.iconQuickTitle,
                subtitle: L10n.Settings.iconQuickDescription,
                icon: "app.badge"
            ) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(panelAccent.opacity(colorScheme == .dark ? 0.18 : 0.12))

                        Image(nsImage: currentAppIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(12)
                    }
                    .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(iconDisplayName(savedIconSettings.icon))
                            .font(.headline)
                        Text(L10n.Settings.iconLiveApply)
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
            }
        }
    }

    private var appearanceTab: some View {
        pageScroll {
            settingsHero(
                eyebrow: L10n.Settings.heroAppearance,
                title: L10n.Settings.iconTitle,
                subtitle: L10n.Settings.iconDescription,
                accessory: AnyView(
                    heroMetrics {
                        heroMetric(
                            value: iconDisplayName(builtInIconSelection),
                            label: L10n.Settings.iconBuiltInTitle,
                            systemImage: "sparkles.square.filled.on.square"
                        )
                        heroMetric(
                            value: L10n.Settings.iconLiveApplyShort,
                            label: L10n.Settings.iconPreview,
                            systemImage: "bolt"
                        )
                    }
                )
            )

            settingsCard(
                title: L10n.Settings.iconPreview,
                subtitle: L10n.Settings.iconLiveApply,
                icon: "photo.on.rectangle"
            ) {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        panelAccentStrong.opacity(colorScheme == .dark ? 0.42 : 0.18),
                                        Color(nsColor: .controlBackgroundColor),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(nsImage: draftAppIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(16)
                    }
                    .frame(width: 108, height: 108)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(iconDisplayName(builtInIconSelection))
                            .font(.headline)
                        Text(L10n.Settings.iconDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                if let iconFeedbackMessage {
                    statusBanner(
                        text: iconFeedbackMessage,
                        tone: iconFeedbackIsError ? .danger : .success
                    )
                }
            }

            settingsCard(
                title: L10n.Settings.iconBuiltInTitle,
                subtitle: L10n.Settings.iconPresetDescription,
                icon: "square.grid.2x2"
            ) {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(Ghostty.MacOSIcon.builtInOptions, id: \.self) { icon in
                        iconPresetButton(for: icon)
                    }
                }
            }
        }
    }

    private func iconPresetButton(for icon: Ghostty.MacOSIcon) -> some View {
        let isSelected = builtInIconSelection == icon

        return Button {
            builtInIconSelection = icon
        } label: {
            VStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? panelAccent.opacity(colorScheme == .dark ? 0.24 : 0.14) : Color(nsColor: .controlBackgroundColor))

                    Image(nsImage: builtInPreviewImage(for: icon))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                }
                .frame(width: 72, height: 72)

                Text(iconDisplayName(icon))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? panelAccent.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? panelAccent : Color(nsColor: .separatorColor).opacity(0.24),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var gatewayTab: some View {
        pageScroll {
            settingsHero(
                eyebrow: L10n.Settings.heroRemote,
                title: L10n.Settings.gatewayTitle,
                subtitle: L10n.Settings.gatewayDescription,
                accessory: AnyView(
                    heroMetrics {
                        heroMetric(
                            value: gatewayEnabled ? L10n.Settings.sidebarGatewayOn : L10n.Settings.sidebarGatewayOff,
                            label: L10n.Settings.gatewayEnabled,
                            systemImage: gatewayEnabled ? "network" : "network.slash"
                        )
                        heroMetric(
                            value: gatewaySemanticProfileTitle,
                            label: L10n.Settings.gatewaySemanticProfile,
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                    }
                )
            )

            settingsCard(
                title: L10n.Settings.gatewayStatus,
                subtitle: appDelegate.controlHarnessGatewayStatusMessage,
                icon: "dot.radiowaves.left.and.right"
            ) {
                Toggle(L10n.Settings.gatewayEnabled, isOn: $gatewayEnabled)
                Toggle(L10n.Settings.gatewayShowQrOnLaunch, isOn: $gatewayShowQrOnLaunch)

                if gatewaySettingsDirty {
                    statusBanner(text: L10n.Settings.gatewayPendingChanges, tone: .warning)
                }
            }

            settingsCard(
                title: L10n.Settings.gatewayPanelConnectionTitle,
                subtitle: L10n.Settings.gatewayPanelConnectionDescription,
                icon: "cable.connector"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    fieldBlock(
                        title: L10n.Settings.gatewayListenHost,
                        help: L10n.Settings.gatewayListenHostHelp
                    ) {
                        TextField("0.0.0.0", text: $gatewayListenHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldBlock(
                        title: L10n.Settings.gatewayPort,
                        help: L10n.Settings.gatewayPortHelp
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("9527", text: $gatewayPortText)
                                .textFieldStyle(.roundedBorder)

                            if let gatewayPortValidationMessage {
                                Text(gatewayPortValidationMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    fieldBlock(
                        title: L10n.Settings.gatewayPairingHost,
                        help: L10n.Settings.gatewayPairingHostHelp
                    ) {
                        TextField(L10n.Settings.gatewayPairingHostPlaceholder, text: $gatewayPairingHost)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            settingsCard(
                title: L10n.Settings.gatewaySemanticProfile,
                subtitle: L10n.Settings.gatewaySemanticProfileHelp,
                icon: "slider.horizontal.3"
            ) {
                Picker(L10n.Settings.gatewaySemanticProfile, selection: $gatewaySemanticProfile) {
                    Text(L10n.Settings.gatewaySemanticProfileGeneric).tag(ControlHarnessSemanticProfile.generic)
                    Text(L10n.Settings.gatewaySemanticProfileCodex).tag(ControlHarnessSemanticProfile.codex)
                    Text(L10n.Settings.gatewaySemanticProfileClaudeCode).tag(ControlHarnessSemanticProfile.claudeCode)
                }
                .pickerStyle(.segmented)
            }

            settingsCard(
                title: L10n.Settings.gatewayPanelActionsTitle,
                subtitle: L10n.Settings.gatewayPanelActionsDescription,
                icon: "wand.and.stars"
            ) {
                HStack(spacing: 12) {
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
            }
        }
    }

    private func pageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func settingsHero(
        eyebrow: String,
        title: String,
        subtitle: String,
        accessory: AnyView
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(panelAccent)

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 540, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            accessory
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                panelAccentStrong.opacity(0.34),
                                Color(nsColor: .controlBackgroundColor).opacity(0.84),
                            ]
                            : [
                                GhoDexPanelPalette.accentSurfaceLight,
                                GhoDexPanelPalette.accentSurfaceLightRaised,
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(roundedBorder(cornerRadius: 26))
    }

    private func heroMetrics<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                content()
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private func heroMetric(value: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: heroMetricMinWidth, idealWidth: 172, maxWidth: 188, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.46))
        )
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCardHeader(title: title, subtitle: subtitle, icon: icon)
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsCardBackground)
        .overlay(roundedBorder(cornerRadius: 24))
    }

    private func settingsSplitCard<Controls: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                settingsCardHeader(title: title, subtitle: subtitle, icon: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)

                settingsControlPane {
                    controls()
                }
                .frame(width: 380, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 16) {
                settingsCardHeader(title: title, subtitle: subtitle, icon: icon)

                settingsControlPane {
                    controls()
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsCardBackground)
        .overlay(roundedBorder(cornerRadius: 24))
    }

    private func settingsCardHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(panelAccent.opacity(colorScheme == .dark ? 0.2 : 0.12))

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(panelAccent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsControlPane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.72 : 0.78))
    }

    private func fieldBlock<Field: View>(
        title: String,
        help: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            field()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum StatusTone {
        case success
        case warning
        case danger
    }

    private func statusBanner(
        text: String,
        tone: StatusTone,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(statusColor(for: tone))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor(for: tone).opacity(colorScheme == .dark ? 0.18 : 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusColor(for tone: StatusTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    private func title(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return L10n.Settings.generalTab
        case .appearance:
            return L10n.Settings.appearanceTab
        case .gateway:
            return L10n.Settings.gatewayTab
        }
    }

    private func subtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return L10n.Settings.sidebarGeneralDetail
        case .appearance:
            return L10n.Settings.sidebarAppearanceDetail
        case .gateway:
            return L10n.Settings.sidebarGatewayDetail
        }
    }

    private func sidebarSubtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return L10n.Settings.sidebarGeneralShort
        case .appearance:
            return L10n.Settings.sidebarAppearanceShort
        case .gateway:
            return L10n.Settings.sidebarGatewayShort
        }
    }

    private func iconName(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return "gearshape.2"
        case .appearance:
            return "app.badge"
        case .gateway:
            return "network"
        }
    }

    private var gatewaySemanticProfileTitle: String {
        switch gatewaySemanticProfile {
        case .generic:
            return L10n.Settings.gatewaySemanticProfileGeneric
        case .codex:
            return L10n.Settings.gatewaySemanticProfileCodex
        case .claudeCode:
            return L10n.Settings.gatewaySemanticProfileClaudeCode
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

    private func syncInputForm(clearFeedback: Bool) {
        mouseBackForwardSwitchesTabs = appDelegate.mouseBackForwardSwitchesTabs
        splitPickerEnabled = appDelegate.splitPickerEnabled

        if clearFeedback {
            inputFeedbackMessage = nil
            inputFeedbackIsError = false
            inputFeedbackScope = nil
        }
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

    private func saveMouseNavigationSettingIfNeeded() {
        guard mouseBackForwardSwitchesTabs != appDelegate.mouseBackForwardSwitchesTabs else { return }

        do {
            try appDelegate.saveMouseBackForwardTabSwitchingSetting(mouseBackForwardSwitchesTabs)
            inputFeedbackMessage = L10n.Settings.mouseNavigationSaved
            inputFeedbackIsError = false
            inputFeedbackScope = .mouseNavigation
        } catch {
            mouseBackForwardSwitchesTabs = appDelegate.mouseBackForwardSwitchesTabs
            inputFeedbackMessage = error.localizedDescription
            inputFeedbackIsError = true
            inputFeedbackScope = .mouseNavigation
        }
    }

    private func saveSplitPickerSettingIfNeeded() {
        guard splitPickerEnabled != appDelegate.splitPickerEnabled else { return }

        do {
            try appDelegate.saveSplitPickerSetting(splitPickerEnabled)
            inputFeedbackMessage = L10n.Settings.splitPickerSaved
            inputFeedbackIsError = false
            inputFeedbackScope = .splitPicker
        } catch {
            splitPickerEnabled = appDelegate.splitPickerEnabled
            inputFeedbackMessage = error.localizedDescription
            inputFeedbackIsError = true
            inputFeedbackScope = .splitPicker
        }
    }

    private func openPrivacySettings(_ destination: AppPermissionPrivacySettingsDestination) {
        permissionsFeedbackMessage = nil
        guard appDelegate.openPrivacySettings(destination) else {
            permissionsFeedbackMessage = L10n.Settings.permissionsOpenSettingsFailed
            return
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
