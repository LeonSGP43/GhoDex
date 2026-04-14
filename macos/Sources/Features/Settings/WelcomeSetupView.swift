import SwiftUI

struct WelcomeSetupView: View {
    @ObservedObject var model: WelcomeSetupModel

    private let iconColumns = [
        GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    appBasicsCard
                    learningCard
                    todoCard
                    browserCard
                    gatewayCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.WelcomeSetup.footerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = model.saveFeedbackMessage {
                    statusMessage(message, tone: model.saveFeedbackTone)
                }

                HStack(spacing: 12) {
                    Button(L10n.WelcomeSetup.openSettings) {
                        model.openSettingsPanel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(L10n.WelcomeSetup.apply) {
                        _ = model.applySetup()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)

                    Button(L10n.WelcomeSetup.finish) {
                        model.finishSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.WelcomeSetup.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(L10n.WelcomeSetup.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.97, green: 0.83, blue: 0.68),
                            Color(red: 0.95, green: 0.91, blue: 0.79),
                            Color(red: 0.88, green: 0.92, blue: 0.96),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var appBasicsCard: some View {
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
                                            ? Color.accentColor.opacity(0.16)
                                            : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            model.builtInIconSelection == icon ? Color.accentColor : Color.black.opacity(0.06),
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

    private var learningCard: some View {
        setupCard(
            title: L10n.WelcomeSetup.learningSectionTitle,
            subtitle: L10n.WelcomeSetup.learningSectionBody
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(L10n.SSHConnections.learningEnable, isOn: $model.learningEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.WelcomeSetup.learningChatWorkspace)
                        .font(.headline)
                    HStack(spacing: 10) {
                        TextField(
                            AITerminalLearningSettings.defaultChatWorkspacePath,
                            text: $model.learningChatWorkspacePath
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(L10n.Settings.browserBrowseButton) {
                            model.browseLearningWorkspace()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(L10n.WelcomeSetup.learningChatWorkspaceHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    pathPreview(model.resolvedLearnWorkspacePath)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.WelcomeSetup.learningNotesRelativePath)
                        .font(.headline)
                    TextField(
                        AITerminalLearningSettings.defaultNotesRelativePath,
                        text: $model.learningNotesRelativePath
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(L10n.WelcomeSetup.learningNotesRelativePathHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    pathPreview(model.resolvedNotesAbsolutePath)
                }

                HStack(spacing: 12) {
                    Button(L10n.SSHConnections.learningInitializeWorkspace) {
                        model.initializeLearningWorkspace()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.learningOperationInProgress)

                    if model.learningOperationInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                if let message = model.learningStatusMessage {
                    statusMessage(message, tone: model.learningStatusTone)
                }
            }
        }
    }

    private var todoCard: some View {
        setupCard(
            title: L10n.WelcomeSetup.todoSectionTitle,
            subtitle: L10n.WelcomeSetup.todoSectionBody
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(L10n.SSHConnections.todoEnable, isOn: $model.todoEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.todoWorkspaceRootPath)
                        .font(.headline)
                    HStack(spacing: 10) {
                        TextField(
                            AITerminalTodoSettings.defaultWorkspaceRootPath,
                            text: $model.todoWorkspaceRootPath
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(L10n.Settings.browserBrowseButton) {
                            model.browseTodoWorkspace()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(L10n.WelcomeSetup.todoWorkspaceRootHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(L10n.SSHConnections.todoInitializeWorkspace) {
                        model.initializeTodoWorkspace()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                if let message = model.todoStatusMessage {
                    statusMessage(message, tone: model.todoStatusTone)
                }
            }
        }
    }

    private var browserCard: some View {
        setupCard(
            title: L10n.WelcomeSetup.browserSectionTitle,
            subtitle: L10n.WelcomeSetup.browserSectionBody
        ) {
            VStack(alignment: .leading, spacing: 16) {
                statusMessage(model.browserRuntimeStatusText, tone: model.browserRuntimeStatusTone)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.Settings.browserProfileSectionTitle)
                        .font(.headline)

                    Toggle(L10n.Settings.browserUseManagedProfile, isOn: $model.browserUsesManagedProfile)

                    if model.browserUsesManagedProfile {
                        pathPreview(model.managedBrowserProfilePath)
                    } else {
                        HStack(spacing: 10) {
                            TextField(
                                L10n.Settings.browserCustomPlaceholder,
                                text: $model.browserProfilePathText
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(L10n.Settings.browserBrowseButton) {
                                model.browseBrowserProfile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.Settings.browserRuntimeSectionTitle)
                        .font(.headline)

                    Toggle(L10n.Settings.browserUseManagedRuntime, isOn: $model.browserUsesManagedRuntime)

                    if model.browserUsesManagedRuntime {
                        pathPreview(model.managedBrowserRuntimePath)
                    } else {
                        HStack(spacing: 10) {
                            TextField(
                                L10n.Settings.browserCustomRuntimePlaceholder,
                                text: $model.browserRuntimePathText
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(L10n.Settings.browserBrowseButton) {
                                model.browseBrowserRuntime()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(model.browserAssessmentText)
                        .font(.caption)
                        .foregroundStyle(color(for: model.browserAssessmentTone))
                        .fixedSize(horizontal: false, vertical: true)

                    if model.browserUsesManagedRuntime {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.managedBrowserRuntimeHintLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 12) {
                        Button(L10n.WelcomeSetup.browserInstallRuntime) {
                            model.installManagedBrowserRuntime()
                        }
                        .buttonStyle(.bordered)
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

    private var gatewayCard: some View {
        setupCard(
            title: L10n.WelcomeSetup.gatewaySectionTitle,
            subtitle: L10n.WelcomeSetup.gatewaySectionBody
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(L10n.Settings.gatewayEnabled, isOn: $model.gatewayEnabled)
                Toggle(L10n.Settings.gatewayShowQrOnLaunch, isOn: $model.gatewayShowQrOnLaunch)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayListenHost)
                        .font(.headline)
                    TextField("0.0.0.0", text: $model.gatewayListenHost)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayListenHostHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayPort)
                        .font(.headline)
                    TextField("9527", text: $model.gatewayPortText)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayPortHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.gatewayPairingHost)
                        .font(.headline)
                    TextField(L10n.Settings.gatewayPairingHostPlaceholder, text: $model.gatewayPairingHost)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.Settings.gatewayPairingHostHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func pathPreview(_ path: String) -> some View {
        Text(path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusMessage(_ text: String, tone: WelcomeSetupModel.StatusTone) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color(for: tone))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color(for: tone).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
}
