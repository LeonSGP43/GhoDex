import AppKit
import SwiftUI

struct WelcomeSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: WelcomeSetupModel

    private let iconColumns = [
        GridItem(.adaptive(minimum: 110, maximum: 144), spacing: 12, alignment: .top)
    ]
    private let guideColumns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14, alignment: .top)
    ]

    private var panelAccent: Color { GhoDexPanelPalette.accent }
    private var panelAccentStrong: Color { GhoDexPanelPalette.accentStrong }
    private var panelAccentSoft: Color { GhoDexPanelPalette.accentSoft }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stepRail
                    .frame(width: 272)

                Divider()

                stageContent
            }

            Divider()

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient)
        .tint(panelAccent)
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
                    panelAccentSoft.opacity(0.48),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.WelcomeSetup.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(L10n.WelcomeSetup.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.orderedSteps) { step in
                    stepRailItem(for: step)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.stepProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ProgressView(
                    value: Double(model.currentStepIndex + 1),
                    total: Double(model.orderedSteps.count)
                )
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
            }
            .padding(16)
            .background(subpanelFill(cornerRadius: 18))
            .overlay(roundedBorder(cornerRadius: 18))
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(railBackground)
    }

    private var railBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.14, green: 0.15, blue: 0.18),
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                ]
                : [
                    Color.white.opacity(0.94),
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func stepRailItem(for step: WelcomeSetupModel.Step) -> some View {
        let isCurrent = step == model.currentStep
        let index = (model.orderedSteps.firstIndex(of: step) ?? 0) + 1

        return Button {
            model.currentStep = step
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? panelAccent : Color(nsColor: .controlBackgroundColor))
                    Text("\(index)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCurrent ? Color.white : Color.primary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title(for: step))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(model.body(for: step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isCurrent ? panelAccent.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isCurrent ? panelAccent.opacity(0.42) : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var stageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard

                switch model.currentStep {
                case .workspace:
                    workspaceStage
                case .app:
                    appStage
                case .browser:
                    browserStage
                case .gateway:
                    gatewayStage
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.currentStepTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(model.currentStepBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.stepProgressText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(panelAccent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .overlay(roundedBorder(cornerRadius: 24))
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            panelAccentStrong.opacity(0.72),
                            GhoDexPanelPalette.accentSurfaceDark.opacity(0.96),
                            Color(red: 0.12, green: 0.14, blue: 0.20),
                        ]
                        : [
                            panelAccentSoft.opacity(0.96),
                            Color.white.opacity(0.98),
                            GhoDexPanelPalette.accentSurfaceLight.opacity(0.88),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.52),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var workspaceStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.currentStepFeatureGuides.isEmpty {
                setupCard(
                    title: L10n.WelcomeSetup.guideSectionTitle,
                    subtitle: L10n.WelcomeSetup.guideSectionBody
                ) {
                    LazyVGrid(columns: guideColumns, spacing: 14) {
                        ForEach(model.currentStepFeatureGuides) { guide in
                            featureGuideCard(guide)
                        }
                    }
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.workspaceRootTitle,
                subtitle: L10n.WelcomeSetup.workspaceRootBody
            ) {
                HStack(spacing: 10) {
                    TextField(
                        WelcomeSetupModel.defaultWorkspaceRootPath,
                        text: $model.ghodexWorkspaceRootPath
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(L10n.Settings.browserBrowseButton) {
                        model.browseWorkspaceRoot()
                    }
                    .buttonStyle(.bordered)
                }

                pathPreview(model.resolvedWorkspaceRootPath)

                Text(model.defaultWorkspaceRootHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 18) {
                    Toggle(L10n.SSHConnections.learningEnable, isOn: $model.learningEnabled)
                    Toggle(L10n.SSHConnections.todoEnable, isOn: $model.todoEnabled)
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.workspacePreviewTitle,
                subtitle: L10n.WelcomeSetup.workspacePreviewBody
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.workspacePathPreviews) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            pathPreview(item.path)
                        }
                    }
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.workspaceAdvancedTitle,
                subtitle: L10n.WelcomeSetup.workspaceAdvancedBody
            ) {
                DisclosureGroup(isExpanded: $model.showAdvancedPaths) {
                    VStack(alignment: .leading, spacing: 14) {
                        advancedPathField(
                            title: L10n.WelcomeSetup.workspacePreviewChat,
                            text: $model.learningChatWorkspacePath,
                            placeholder: model.defaultLearningChatWorkspacePath,
                            action: model.browseLearningWorkspace
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.WelcomeSetup.workspacePreviewNotes)
                                .font(.headline)
                            TextField(
                                AITerminalLearningSettings.defaultNotesRelativePath,
                                text: $model.learningNotesRelativePath
                            )
                            .textFieldStyle(.roundedBorder)
                            pathPreview(model.resolvedNotesAbsolutePath)
                        }

                        advancedPathField(
                            title: L10n.WelcomeSetup.workspacePreviewTodo,
                            text: $model.todoWorkspaceRootPath,
                            placeholder: model.defaultTodoWorkspacePath,
                            action: model.browseTodoWorkspace
                        )

                        advancedPathField(
                            title: L10n.WelcomeSetup.workspacePreviewBrowserProfile,
                            text: $model.browserProfilePathText,
                            placeholder: model.defaultBrowserProfilePath,
                            action: model.browseBrowserProfile
                        )

                        advancedPathField(
                            title: L10n.WelcomeSetup.workspacePreviewBrowserRuntime,
                            text: $model.browserRuntimePathText,
                            placeholder: model.defaultBrowserRuntimePath,
                            action: model.browseBrowserRuntime
                        )
                    }
                    .padding(.top, 12)
                } label: {
                    Text(L10n.WelcomeSetup.workspaceAdvancedToggle)
                        .font(.headline)
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.workspacePrepare,
                subtitle: L10n.WelcomeSetup.footerNote
            ) {
                HStack(spacing: 12) {
                    Button(L10n.WelcomeSetup.workspacePrepare) {
                        model.prepareWorkspaceLayout()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)

                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let message = model.workspaceStatusMessage {
                    statusMessage(message, tone: model.workspaceStatusTone)
                }

                if let message = model.learningStatusMessage {
                    statusMessage(message, tone: model.learningStatusTone)
                }

                if let message = model.todoStatusMessage {
                    statusMessage(message, tone: model.todoStatusTone)
                }
            }
        }
    }

    private var appStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.currentStepFeatureGuides.isEmpty {
                setupCard(
                    title: L10n.WelcomeSetup.guideSectionTitle,
                    subtitle: L10n.WelcomeSetup.guideSectionBody
                ) {
                    LazyVGrid(columns: guideColumns, spacing: 14) {
                        ForEach(model.currentStepFeatureGuides) { guide in
                            featureGuideCard(guide)
                        }
                    }
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.appSectionTitle,
                subtitle: L10n.WelcomeSetup.appSectionBody
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.languageTitle)
                            .font(.headline)
                        Picker(L10n.Settings.languageTitle, selection: $model.selectedLanguage) {
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

                    if model.needsRestart {
                        HStack(spacing: 12) {
                            Text(L10n.Settings.languageRestartRequired)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.Settings.restartNow) {
                                model.restartNow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L10n.Settings.mouseNavigationSwitchTabs, isOn: $model.mouseBackForwardSwitchesTabs)
                        Text(L10n.Settings.mouseNavigationDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 16) {
                            Image(nsImage: model.previewIconImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 72, height: 72)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.Settings.iconBuiltInTitle)
                                    .font(.headline)
                                Text(L10n.Settings.iconDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        LazyVGrid(columns: iconColumns, spacing: 12) {
                            ForEach(Ghostty.MacOSIcon.builtInOptions, id: \.self) { icon in
                                Button {
                                    model.builtInIconSelection = icon
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(nsImage: model.previewImage(for: icon))
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFit()
                                            .frame(width: 56, height: 56)

                                        Text(model.iconDisplayName(icon))
                                            .font(.caption.weight(.medium))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(model.builtInIconSelection == icon
                                                ? panelAccent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                                                : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.88 : 0.72))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                model.builtInIconSelection == icon ? panelAccent : Color(nsColor: .separatorColor).opacity(0.2),
                                                lineWidth: model.builtInIconSelection == icon ? 2 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var browserStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.currentStepFeatureGuides.isEmpty {
                setupCard(
                    title: L10n.WelcomeSetup.guideSectionTitle,
                    subtitle: L10n.WelcomeSetup.guideSectionBody
                ) {
                    LazyVGrid(columns: guideColumns, spacing: 14) {
                        ForEach(model.currentStepFeatureGuides) { guide in
                            featureGuideCard(guide)
                        }
                    }
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.browserSectionTitle,
                subtitle: L10n.WelcomeSetup.browserSectionBody
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    statusMessage(model.browserRuntimeStatusText, tone: model.browserRuntimeStatusTone)

                    Text(L10n.WelcomeSetup.browserDownloadHelp(model.resolvedBrowserRuntimePath))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Settings.browserProfileSectionTitle)
                            .font(.headline)
                        pathPreview(model.resolvedBrowserProfilePath)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Settings.browserRuntimeSectionTitle)
                            .font(.headline)
                        pathPreview(model.resolvedBrowserRuntimePath)
                    }

                    Text(model.browserAssessmentText)
                        .font(.caption)
                        .foregroundStyle(color(for: model.browserAssessmentTone))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(L10n.WelcomeSetup.browserInstallRuntime) {
                            model.installManagedBrowserRuntime()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canInstallManagedRuntime)

                        Button(L10n.WelcomeSetup.browserRetryActivation) {
                            model.retryBrowserRuntimeActivation()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canRetryBrowserActivation)

                        Spacer()
                    }

                    if let installStatus = model.browserInstallStatusText {
                        statusMessage(installStatus, tone: model.browserInstallStatusTone)
                    }
                }
            }
        }
    }

    private var gatewayStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.currentStepFeatureGuides.isEmpty {
                setupCard(
                    title: L10n.WelcomeSetup.guideSectionTitle,
                    subtitle: L10n.WelcomeSetup.guideSectionBody
                ) {
                    LazyVGrid(columns: guideColumns, spacing: 14) {
                        ForEach(model.currentStepFeatureGuides) { guide in
                            featureGuideCard(guide)
                        }
                    }
                }
            }

            setupCard(
                title: L10n.WelcomeSetup.gatewaySectionTitle,
                subtitle: L10n.WelcomeSetup.gatewaySectionBody
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(L10n.Settings.gatewayEnabled, isOn: $model.gatewayEnabled)
                    Toggle(L10n.Settings.gatewayShowQrOnLaunch, isOn: $model.gatewayShowQrOnLaunch)

                    fieldBlock(
                        title: L10n.Settings.gatewayListenHost,
                        value: $model.gatewayListenHost,
                        placeholder: "0.0.0.0",
                        help: L10n.Settings.gatewayListenHostHelp
                    )

                    fieldBlock(
                        title: L10n.Settings.gatewayPort,
                        value: $model.gatewayPortText,
                        placeholder: "9527",
                        help: L10n.Settings.gatewayPortHelp
                    )

                    fieldBlock(
                        title: L10n.Settings.gatewayPairingHost,
                        value: $model.gatewayPairingHost,
                        placeholder: L10n.Settings.gatewayPairingHostPlaceholder,
                        help: L10n.Settings.gatewayPairingHostHelp
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.gatewaySemanticProfile)
                            .font(.headline)
                        Picker(L10n.Settings.gatewaySemanticProfile, selection: $model.gatewaySemanticProfile) {
                            Text(L10n.Settings.gatewaySemanticProfileGeneric).tag(ControlHarnessSemanticProfile.generic)
                            Text(L10n.Settings.gatewaySemanticProfileCodex).tag(ControlHarnessSemanticProfile.codex)
                            Text(L10n.Settings.gatewaySemanticProfileClaudeCode).tag(ControlHarnessSemanticProfile.claudeCode)
                        }
                        .pickerStyle(.segmented)
                    }

                    if !model.gatewayStatusMessage.isEmpty {
                        statusMessage(model.gatewayStatusMessage, tone: .neutral)
                    }
                }
            }
        }
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = model.saveFeedbackMessage {
                statusMessage(message, tone: model.saveFeedbackTone)
            }

            HStack(spacing: 12) {
                Button(L10n.WelcomeSetup.openSettings) {
                    model.openSettingsPanel()
                }
                .buttonStyle(.bordered)

                if model.canGoBack {
                    Button(L10n.WelcomeSetup.back) {
                        model.goToPreviousStep()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                }

                Spacer()

                if model.isLastStep {
                    Button(L10n.WelcomeSetup.finish) {
                        model.finishSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                } else {
                    Button(L10n.WelcomeSetup.next) {
                        model.goToNextStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(footerBackground)
    }

    private var footerBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.13, green: 0.14, blue: 0.17),
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                ]
                : [
                    Color.white.opacity(0.94),
                    Color(red: 0.96, green: 0.97, blue: 0.985),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func setupCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceFill(cornerRadius: 20))
        .overlay(roundedBorder(cornerRadius: 20))
    }

    private func advancedPathField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.Settings.browserBrowseButton) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func featureGuideCard(_ guide: WelcomeSetupModel.FeatureGuideItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: guide.iconSystemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(panelAccent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(panelAccent.opacity(colorScheme == .dark ? 0.14 : 0.1))
                    )

                Text(guide.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(guide.summary)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(guide.usage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(subpanelFill(cornerRadius: 16))
        .overlay(roundedBorder(cornerRadius: 16))
    }

    private func fieldBlock(
        title: String,
        value: Binding<String>,
        placeholder: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pathPreview(_ path: String) -> some View {
        Text(path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.78 : 1))
            )
            .overlay(roundedBorder(cornerRadius: 12))
    }

    private func statusMessage(_ text: String, tone: WelcomeSetupModel.StatusTone) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color(for: tone))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color(for: tone).opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color(for: tone).opacity(colorScheme == .dark ? 0.38 : 0.2), lineWidth: 1)
            )
    }

    private func color(for tone: WelcomeSetupModel.StatusTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    private func surfaceFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
    }

    private func subpanelFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.035),
                        ]
                        : [
                            Color.white.opacity(0.92),
                            Color(red: 0.96, green: 0.97, blue: 0.99),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func roundedBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.24 : 0.1), lineWidth: 1)
    }
}
