import AppKit
import Foundation
import SwiftUI

struct SSHConnectionsView: View {
    @ObservedObject private var presentation: SSHConnectionsPresentationState

    @MainActor
    private struct ConnectionsSnapshot {
        var allConnectionHosts: [AITerminalHost]
        var allConnectionHostLookup: [String: AITerminalHost]
        var displayFavoriteHosts: [AITerminalHost]
        var displayRecentHosts: [AITerminalHost]
        var displaySavedHosts: [AITerminalHost]
        var displayImportedHosts: [AITerminalHost]
        var displaySavedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate]
        var favoriteHostIDs: Set<String>
        var latestRecentRecordsByHostID: [String: AITerminalRecentHostRecord]
        var remoteSessionsByHostID: [String: [AITerminalRemoteSessionSummary]]
        var activeSessionHostIDs: Set<String>
        var savedHostIDs: Set<String>
        var importedHostIDs: Set<String>
        var overriddenImportedHostIDs: Set<String>
        var availableHostNamesByID: [String: String]

        init(store: AITerminalManagerStore, searchText: String) {
            let savedHosts = store.configuration.savedHosts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let overrideLookup = Dictionary(
                uniqueKeysWithValues: store.configuration.importedHostOverrides.map { ($0.id, $0) }
            )
            let mergedImportedHosts = store.importedSSHHosts.map { host in
                guard let override = overrideLookup[host.id] else { return host }
                var merged = host
                merged.name = override.name
                merged.sshAlias = override.sshAlias
                merged.hostname = override.hostname
                merged.user = override.user
                merged.port = override.port
                merged.defaultDirectory = override.defaultDirectory
                merged.authMode = override.authMode
                return merged
            }
            .sorted { (lhs: AITerminalHost, rhs: AITerminalHost) in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            var availableHosts: [AITerminalHost] = [AITerminalHost.local]
            var seenHostIDs: Set<String> = [AITerminalHost.local.id]
            for host in savedHosts where seenHostIDs.insert(host.id).inserted {
                availableHosts.append(host)
            }
            for host in mergedImportedHosts where seenHostIDs.insert(host.id).inserted {
                availableHosts.append(host)
            }
            availableHosts.sort { lhs, rhs in
                if lhs.id == AITerminalHost.local.id { return true }
                if rhs.id == AITerminalHost.local.id { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            let allConnectionHosts = availableHosts.filter { !$0.isLocal }
            let hostLookup = Dictionary(uniqueKeysWithValues: allConnectionHosts.map { ($0.id, $0) })
            let favoriteHostIDs = Set(store.configuration.favoriteHostIDs)
            let recentRecords = store.configuration.recentHosts.sorted { $0.connectedAt > $1.connectedAt }
            let latestRecentRecordsByHostID = recentRecords.reduce(
                into: [String: AITerminalRecentHostRecord]()
            ) { partialResult, record in
                guard partialResult[record.id] == nil else { return }
                partialResult[record.id] = record
            }
            let remoteSessionsByHostID = Dictionary(grouping: store.remoteSessions, by: \.hostID)
            let activeSessionHostIDs = Set(remoteSessionsByHostID.keys)
            let savedHostIDs = Set(savedHosts.map(\.id))
            let importedHostIDs = Set(store.importedSSHHosts.map(\.id))
            let overriddenImportedHostIDs = Set(store.configuration.importedHostOverrides.map(\.id))
            let availableHostNamesByID = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0.name) })
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            func matches(_ host: AITerminalHost) -> Bool {
                guard !query.isEmpty else { return true }
                return host.name.localizedCaseInsensitiveContains(query)
                    || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
                    || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
                    || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
                    || host.startupCommands.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            }

            let filteredFavoriteHosts = store.configuration.favoriteHostIDs
                .compactMap { hostLookup[$0] }
                .filter(matches)
            let displayFavoriteHosts = SSHConnectionsView.sidebarFavoriteHosts(
                favoriteHosts: filteredFavoriteHosts
            )

            let filteredRecentHosts = recentRecords
                .compactMap { hostLookup[$0.id] }
                .filter(matches)
            let displayRecentHosts = SSHConnectionsView.sidebarRecentHosts(
                recentHosts: filteredRecentHosts,
                favoriteHosts: displayFavoriteHosts
            )

            let filteredSavedHosts = savedHosts.filter(matches)
            let displaySavedHosts = SSHConnectionsView.sidebarSavedHosts(
                savedHosts: filteredSavedHosts,
                favoriteHosts: displayFavoriteHosts,
                recentHosts: displayRecentHosts
            )

            let filteredImportedHosts = mergedImportedHosts.filter(matches)
            let displayImportedHosts = SSHConnectionsView.sidebarImportedHosts(
                importedHosts: filteredImportedHosts,
                favoriteHosts: displayFavoriteHosts,
                savedHosts: filteredSavedHosts,
                recentHosts: displayRecentHosts
            )

            let displaySavedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate]
            if query.isEmpty {
                displaySavedWorkspaceTemplates = store.savedWorkspaceTemplates
            } else {
                displaySavedWorkspaceTemplates = store.savedWorkspaceTemplates.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
            }

            self.allConnectionHosts = allConnectionHosts
            self.allConnectionHostLookup = hostLookup
            self.displayFavoriteHosts = displayFavoriteHosts
            self.displayRecentHosts = displayRecentHosts
            self.displaySavedHosts = displaySavedHosts
            self.displayImportedHosts = displayImportedHosts
            self.displaySavedWorkspaceTemplates = displaySavedWorkspaceTemplates
            self.favoriteHostIDs = favoriteHostIDs
            self.latestRecentRecordsByHostID = latestRecentRecordsByHostID
            self.remoteSessionsByHostID = remoteSessionsByHostID
            self.activeSessionHostIDs = activeSessionHostIDs
            self.savedHostIDs = savedHostIDs
            self.importedHostIDs = importedHostIDs
            self.overriddenImportedHostIDs = overriddenImportedHostIDs
            self.availableHostNamesByID = availableHostNamesByID
        }
    }

    private enum ConnectionEditorType: String, CaseIterable, Identifiable {
        case ssh
        case localmcd

        var id: String { rawValue }

        init(_ transport: AITerminalTransport) {
            switch transport {
            case .localmcd:
                self = .localmcd
            case .local, .ssh:
                self = .ssh
            }
        }

        var transport: AITerminalTransport {
            switch self {
            case .ssh:
                return .ssh
            case .localmcd:
                return .localmcd
            }
        }

        var displayName: String {
            switch self {
            case .ssh:
                return L10n.SSHConnections.connectionTypeSSH
            case .localmcd:
                return L10n.SSHConnections.connectionTypeLocalMCD
            }
        }
    }

    private static let learningLogDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let todoTimelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private struct WorkspacePreviewItem: Identifiable {
        let id: String
        let title: String
        let path: String
    }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appDelegate: AppDelegate
    @EnvironmentObject private var store: AITerminalManagerStore

    @State private var hostEditorType: ConnectionEditorType = .ssh
    @State private var hostName = ""
    @State private var hostAlias = ""
    @State private var hostHostname = ""
    @State private var hostUser = ""
    @State private var hostPort = ""
    @State private var hostDefaultDirectory = ""
    @State private var hostStartupCommands = ""
    @State private var hostPassword = ""
    @State private var hostAuthMode: AITerminalHostAuthMode = .system
    @State private var editingHostID: String?
    @State private var isPresentingEditor = false
    @State private var selectedHostID: String?
    @State private var selectedSavedWorkspaceID: String?
    @State private var hostSearchText = ""

    @State private var todoEnabled = true
    @State private var todoWorkspaceRootPath = ""
    @State private var todoShowCompletedItems = true
    @State private var todoSelectedDate = Date.now
    @State private var todoSidebarEdge: AITerminalTodoSidebarEdge = .leading
    @State private var todoWorkspaceOverlayVisible = true
    @State private var todoWorkspaceOverlayCorner: AITerminalTodoOverlayCorner = .topLeading
    @State private var todoDocument = AITerminalTodoDayDocument()
    @State private var todoDraftTitle = ""
    @State private var todoDraftNotes = ""
    @State private var todoEditingItemID: UUID?
    @State private var todoEditingTitle = ""
    @State private var todoEditingNotes = ""
    @State private var todoStatusMessage: String?

    @State private var learningEnabled = true
    @State private var workspaceRootPathText = AITerminalWorkspaceDefaults.defaultWorkspaceRootPath
    @State private var showAdvancedWorkspacePaths = false
    @State private var learningChatWorkspacePath = ""
    @State private var learningNotesRelativePath = AITerminalLearningSettings.defaultNotesRelativePath
    @State private var learningCommandTemplate = ""
    @State private var learningStatusMessage: String?
    @State private var managedSkillStatuses: [AITerminalManagerStore.ManagedSkillRepositoryStatus] = []
    @State private var expandedLearningLogIDs: Set<UUID> = []
    @State private var learningOperationInProgress = false
    @State private var initializeChatWorkspaceCandidate = ""
    @State private var showingInitializeConfirmation = false
    @State private var heartbeatQueueEnabled = true
    @State private var heartbeatIntervalSecondsText = "5"
    @State private var heartbeatMaxConcurrentTasks = 4
    @State private var queueCommandInput = ""
    @State private var queueScheduleEnabled = false
    @State private var queueExecuteAt = Date().addingTimeInterval(60)
    @State private var queueStatusMessage: String?
    @State private var browserProfilePathText = ""
    @State private var browserRuntimePathText = ""
    @State private var browserSaveMessage: String?
    @State private var browserErrorMessage: String?

    private var panelAccent: Color { GhoDexPanelPalette.accent }
    private var panelAccentStrong: Color { GhoDexPanelPalette.accentStrong }
    private var panelAccentSoft: Color { GhoDexPanelPalette.accentSoft }

    init(presentation: SSHConnectionsPresentationState) {
        self.presentation = presentation
    }

    private var selectedTab: Binding<SSHConnectionsPanelTab> {
        Binding(
            get: { presentation.selectedTab },
            set: { presentation.selectedTab = $0 }
        )
    }

    private var todoWorkspaceTargets: [AITerminalTodoWorkspaceTarget] {
        store.liveTodoWorkspaceTargets()
    }

    private var focusedTodoWorkspaceTarget: AITerminalTodoWorkspaceTarget? {
        guard let focusedID = presentation.todoFocusedWorkspaceID else { return nil }
        return todoWorkspaceTargets.first(where: { $0.workspaceID == focusedID })
    }

    private var currentTab: SSHConnectionsPanelTab {
        presentation.selectedTab
    }

    private var connectionsSnapshot: ConnectionsSnapshot {
        ConnectionsSnapshot(store: store, searchText: hostSearchText)
    }

    private var resolvedWorkspaceRootPath: String {
        let trimmed = workspaceRootPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AITerminalWorkspaceDefaults.defaultWorkspaceRootPath
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private var defaultLearningChatWorkspacePath: String {
        AITerminalWorkspaceDefaults.chatWorkspacePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    private var resolvedLearningChatWorkspacePath: String {
        guard showAdvancedWorkspacePaths else {
            return defaultLearningChatWorkspacePath
        }
        return resolvedDirectoryOverride(
            learningChatWorkspacePath,
            fallback: defaultLearningChatWorkspacePath
        )
    }

    private var resolvedLearnWorkspacePath: String {
        AITerminalLearningSettings.learnWorkspacePath(
            fromChatWorkspacePath: resolvedLearningChatWorkspacePath
        )
    }

    private var resolvedNotesRelativePath: String {
        let trimmed = learningNotesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if showAdvancedWorkspacePaths, !trimmed.isEmpty {
            return trimmed
        }
        return AITerminalLearningSettings.defaultNotesRelativePath
    }

    private var resolvedNotesAbsolutePath: String {
        let normalized = AITerminalWorkspaceDefaults.normalizedNotesPath(resolvedNotesRelativePath)
        if normalized.hasPrefix("/") {
            return normalized
        }
        return URL(fileURLWithPath: resolvedLearnWorkspacePath, isDirectory: true)
            .appendingPathComponent(normalized, isDirectory: false)
            .path
    }

    private var defaultTodoWorkspacePath: String {
        AITerminalWorkspaceDefaults.todoWorkspacePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    private var resolvedTodoWorkspacePath: String {
        guard showAdvancedWorkspacePaths else {
            return defaultTodoWorkspacePath
        }
        return resolvedDirectoryOverride(
            todoWorkspaceRootPath,
            fallback: defaultTodoWorkspacePath
        )
    }

    private var defaultBrowserProfilePath: String {
        AITerminalWorkspaceDefaults.browserProfilePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    private var resolvedBrowserProfilePath: String {
        guard showAdvancedWorkspacePaths else {
            return defaultBrowserProfilePath
        }
        return resolvedDirectoryOverride(
            browserProfilePathText,
            fallback: defaultBrowserProfilePath
        )
    }

    private var defaultBrowserRuntimePath: String {
        AITerminalWorkspaceDefaults.browserRuntimePath(workspaceRootPath: resolvedWorkspaceRootPath)
    }

    private var resolvedBrowserRuntimePath: String {
        guard showAdvancedWorkspacePaths else {
            return defaultBrowserRuntimePath
        }
        return resolvedDirectoryOverride(
            browserRuntimePathText,
            fallback: defaultBrowserRuntimePath
        )
    }

    private var workspaceRootHint: String {
        L10n.WelcomeSetup.workspaceRootDefaultHint(AITerminalWorkspaceDefaults.defaultWorkspaceRootPath)
    }

    var body: some View {
        ZStack {
            workspaceBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let lastError = store.lastError, !lastError.isEmpty {
                    errorBanner(lastError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                switch presentation.selectedTab {
                case .connections:
                    connectionsTabContent

                case .todo:
                    todoTabContent

                case .learning:
                    learningTabContent

                case .taskQueue:
                    taskQueueTabContent

                case .browser:
                    browserTabContent
                case .preferences:
                    preferencesTabContent
                }
            }
        }
        .frame(minWidth: 1240, minHeight: 780)
        .tint(panelAccent)
        .sheet(isPresented: $isPresentingEditor) {
            hostEditorSheet
        }
        .onAppear {
            syncSelection()
            syncWorkspacePathSettings()
            syncTodoSettings()
            syncLearningSettings()
            syncTaskQueueSettings()
            browserSaveMessage = nil
            browserErrorMessage = nil
        }
        .onChange(of: allConnectionHosts.map(\.id)) { _ in
            syncSelection()
        }
        .onChange(of: store.configurationRevision) { _ in
            syncSelection()
            syncWorkspacePathSettings()
            syncTodoSettings()
            syncLearningSettings()
            syncTaskQueueSettings()
            browserSaveMessage = nil
            browserErrorMessage = nil
        }
        .onChange(of: store.todoRevision) { _ in
            refreshTodoDocument()
        }
        .onReceive(appDelegate.$browserProfilePathOverride) { _ in
            syncWorkspacePathSettings()
        }
        .onReceive(appDelegate.$browserRuntimePathOverride) { _ in
            syncWorkspacePathSettings()
        }
        .alert(L10n.SSHConnections.learningInitializeConfirmTitle, isPresented: $showingInitializeConfirmation) {
            Button(L10n.SSHConnections.learningInitializeConfirmAction) {
                confirmInitializeLearningWorkspace()
            }
            Button(L10n.AITerminalManager.cancelEdit, role: .cancel) {}
        } message: {
            Text(L10n.SSHConnections.learningInitializeConfirmMessage(initializeChatWorkspaceCandidate))
        }
    }

    private var workspaceBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                ]
                : [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.97, green: 0.96, blue: 0.94),
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SSHConnectionsPanelTab.allCases) { tab in
                    navigationButton(for: tab)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.18 : 0.1), lineWidth: 1)
        )
    }

    private var connectionsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHero(
                tab: .connections,
                title: L10n.SSHConnections.connectionsPageTitle,
                subtitle: L10n.SSHConnections.connectionsPageSubtitle
            )

            HStack(alignment: .top, spacing: 20) {
                sidebarPanel
                    .frame(width: 340)

                detailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var learningTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHero(
                    tab: .learning,
                    title: L10n.SSHConnections.learningTitle,
                    subtitle: L10n.SSHConnections.learningSubtitle
                )

                Toggle(L10n.SSHConnections.learningEnable, isOn: $learningEnabled)

                workspaceLayoutCard(
                    previewItems: [
                        .init(id: "chat", title: L10n.WelcomeSetup.workspacePreviewChat, path: resolvedLearningChatWorkspacePath),
                        .init(id: "learn", title: L10n.WelcomeSetup.workspacePreviewLearn, path: resolvedLearnWorkspacePath),
                        .init(id: "notes", title: L10n.WelcomeSetup.workspacePreviewNotes, path: resolvedNotesAbsolutePath),
                    ]
                ) {
                    advancedPathField(
                        title: L10n.WelcomeSetup.workspacePreviewChat,
                        text: $learningChatWorkspacePath,
                        placeholder: defaultLearningChatWorkspacePath
                    ) {
                        if let path = chooseDirectory(currentPath: learningChatWorkspacePath) {
                            showAdvancedWorkspacePaths = true
                            learningChatWorkspacePath = path
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.WelcomeSetup.workspacePreviewNotes)
                            .font(.headline)
                        TextField(
                            AITerminalLearningSettings.defaultNotesRelativePath,
                            text: $learningNotesRelativePath
                        )
                        .textFieldStyle(.roundedBorder)
                        monoPathLabel(resolvedNotesAbsolutePath)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.learningCommandTemplate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        AITerminalLearningSettings.defaultCommandTemplate,
                        text: $learningCommandTemplate
                    )
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.learningSupportedPlaceholders)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(learningSupportedPlaceholdersText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                managedSkillRepositoryPanel

                learningLogPanel

                HStack(spacing: 12) {
                    Button(L10n.SSHConnections.learningInitializeWorkspace) {
                        requestInitializeLearningWorkspace()
                    }
                    .disabled(learningOperationInProgress)

                    Button(L10n.SSHConnections.learningSave) {
                        persistLearningSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(learningOperationInProgress)

                    if learningOperationInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let learningStatusMessage, !learningStatusMessage.isEmpty {
                        Text(learningStatusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.SSHConnections.learningInitializeWorkspaceHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var normalizedBrowserProfilePath: String? {
        AITerminalWorkspaceDefaults.normalizedDirectoryPath(resolvedBrowserProfilePath)
    }

    private var effectiveBrowserProfilePath: String? {
        AITerminalWorkspaceDefaults.normalizedDirectoryPath(appDelegate.browserProfilePathOverride ?? "")
    }

    private var normalizedBrowserRuntimePath: String? {
        AITerminalWorkspaceDefaults.normalizedDirectoryPath(resolvedBrowserRuntimePath)
    }

    private var effectiveBrowserRuntimePath: String? {
        AITerminalWorkspaceDefaults.normalizedDirectoryPath(appDelegate.browserRuntimePathOverride ?? "")
    }

    private var browserSettingsDirty: Bool {
        normalizedBrowserProfilePath != effectiveBrowserProfilePath ||
            normalizedBrowserRuntimePath != effectiveBrowserRuntimePath
    }

    private var todoTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHero(
                    tab: .todo,
                    title: L10n.SSHConnections.todoTitle,
                    subtitle: L10n.SSHConnections.todoSubtitle
                )

                Toggle(L10n.SSHConnections.todoEnable, isOn: $todoEnabled)

                workspaceLayoutCard(
                    previewItems: [
                        .init(id: "todo", title: L10n.WelcomeSetup.workspacePreviewTodo, path: resolvedTodoWorkspacePath),
                    ]
                ) {
                    advancedPathField(
                        title: L10n.WelcomeSetup.workspacePreviewTodo,
                        text: $todoWorkspaceRootPath,
                        placeholder: defaultTodoWorkspacePath
                    ) {
                        if let path = chooseDirectory(currentPath: todoWorkspaceRootPath) {
                            showAdvancedWorkspacePaths = true
                            todoWorkspaceRootPath = path
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.todoDayFilePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedTodoDayFilePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                todoPresentationCard

                HStack(alignment: .center, spacing: 12) {
                    Button(L10n.SSHConnections.todoDateYesterday) {
                        todoSelectedDate = Calendar.current.date(byAdding: .day, value: -1, to: todoSelectedDate) ?? todoSelectedDate
                        persistTodoDateSelection()
                    }
                    .buttonStyle(.bordered)

                    DatePicker(
                        "",
                        selection: $todoSelectedDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: todoSelectedDate) { _ in
                        persistTodoDateSelection()
                    }

                    Button(L10n.SSHConnections.todoDateToday) {
                        todoSelectedDate = .now
                        persistTodoDateSelection()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.SSHConnections.todoDateTomorrow) {
                        todoSelectedDate = Calendar.current.date(byAdding: .day, value: 1, to: todoSelectedDate) ?? todoSelectedDate
                        persistTodoDateSelection()
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 12)

                    Toggle(L10n.SSHConnections.todoShowCompletedItems, isOn: $todoShowCompletedItems)
                        .toggleStyle(.switch)
                        .onChange(of: todoShowCompletedItems) { _ in
                            persistTodoSettings(showSavedMessage: false)
                        }
                }

                todoSummaryCard
                focusedTodoWorkspaceCard
                todoComposerCard
                todoTimelinePanel

                HStack(spacing: 12) {
                    Button(L10n.SSHConnections.todoInitializeWorkspace) {
                        initializeTodoWorkspace()
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.SSHConnections.todoSaveSettings) {
                        persistTodoSettings(showSavedMessage: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)

                    if let todoStatusMessage, !todoStatusMessage.isEmpty {
                        Text(todoStatusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.SSHConnections.todoInitializeWorkspaceHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var browserTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHero(
                    tab: .browser,
                    title: L10n.Settings.browserTitle,
                    subtitle: L10n.Settings.browserDescription
                )

                workspaceLayoutCard(
                    previewItems: [
                        .init(id: "browser_profile", title: L10n.WelcomeSetup.workspacePreviewBrowserProfile, path: resolvedBrowserProfilePath),
                        .init(id: "browser_runtime", title: L10n.WelcomeSetup.workspacePreviewBrowserRuntime, path: resolvedBrowserRuntimePath),
                    ]
                ) {
                    advancedPathField(
                        title: L10n.WelcomeSetup.workspacePreviewBrowserProfile,
                        text: $browserProfilePathText,
                        placeholder: defaultBrowserProfilePath
                    ) {
                        if let path = appDelegate.chooseBrowserProfilePath(currentPath: browserProfilePathText) {
                            showAdvancedWorkspacePaths = true
                            browserProfilePathText = path
                            browserSaveMessage = nil
                            browserErrorMessage = nil
                        }
                    }

                    advancedPathField(
                        title: L10n.WelcomeSetup.workspacePreviewBrowserRuntime,
                        text: $browserRuntimePathText,
                        placeholder: defaultBrowserRuntimePath
                    ) {
                        if let path = appDelegate.chooseBrowserRuntimePath(currentPath: browserRuntimePathText) {
                            showAdvancedWorkspacePaths = true
                            browserRuntimePathText = path
                            browserSaveMessage = nil
                            browserErrorMessage = nil
                        }
                    }
                }

                browserRuntimeSection

                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let browserErrorMessage, !browserErrorMessage.isEmpty {
                            Text(browserErrorMessage)
                                .foregroundStyle(.red)
                        } else if let browserSaveMessage, !browserSaveMessage.isEmpty {
                            Text(browserSaveMessage)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(" ")
                                .foregroundStyle(.clear)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(L10n.Settings.browserSaveButton) {
                        persistBrowserSettings()
                    }
                    .disabled(!browserSettingsDirty)
                }

                Text(L10n.Settings.browserRestartRequired)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var browserRuntimeSection: some View {
        let runtimeAssessment = BrowserPaths.runtimeMediaAssessment(
            runtimePath: resolvedBrowserRuntimePath,
            usesManagedRuntime: false
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Settings.browserRuntimeSectionTitle)
                .font(.headline)

            Text(L10n.Settings.browserRuntimeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            monoPathLabel(resolvedBrowserRuntimePath)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Settings.browserRuntimeMediaTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(runtimeAssessmentMessage(runtimeAssessment))
                    .font(.caption)
                    .foregroundStyle(runtimeAssessmentColor(runtimeAssessment))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(runtimeAssessmentColor(runtimeAssessment).opacity(colorScheme == .dark ? 0.14 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func workspaceLayoutCard<AdvancedContent: View>(
        previewItems: [WorkspacePreviewItem],
        @ViewBuilder advancedContent: @escaping () -> AdvancedContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.WelcomeSetup.workspaceRootTitle)
                    .font(.headline)
                Text(L10n.WelcomeSetup.workspaceRootBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TextField(
                        AITerminalWorkspaceDefaults.defaultWorkspaceRootPath,
                        text: $workspaceRootPathText
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(L10n.Settings.browserBrowseButton) {
                        if let path = chooseDirectory(currentPath: workspaceRootPathText) {
                            workspaceRootPathText = path
                        }
                    }
                    .buttonStyle(.bordered)
                }

                monoPathLabel(resolvedWorkspaceRootPath)

                Text(workspaceRootHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(previewItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        monoPathLabel(item.path)
                    }
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedWorkspacePaths) {
                VStack(alignment: .leading, spacing: 14) {
                    advancedContent()
                }
                .padding(.top, 12)
            } label: {
                Text(L10n.WelcomeSetup.workspaceAdvancedToggle)
                    .font(.headline)
            }
        }
        .padding(14)
        .subpanelSurface()
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
                Button(L10n.Settings.browserBrowseButton, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func monoPathLabel(_ path: String) -> some View {
        Text(path)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func runtimeAssessmentMessage(_ assessment: BrowserRuntimeMediaAssessment) -> String {
        switch assessment.reason {
        case .managedChromiumDistribution:
            return L10n.Settings.browserRuntimeMediaManagedWarning
        case .codecEnabledRuntime:
            return L10n.Settings.browserRuntimeMediaCodecEnabledHint
        case .chromiumBrandedRuntime:
            return L10n.Settings.browserRuntimeMediaChromiumWarning(
                assessment.runtimeSource ?? assessment.runtimePath ?? L10n.Common.untitled
            )
        case .customRuntimeUnverified:
            return L10n.Settings.browserRuntimeMediaCustomHint
        }
    }

    private func runtimeAssessmentColor(_ assessment: BrowserRuntimeMediaAssessment) -> Color {
        switch assessment.reason {
        case .codecEnabledRuntime:
            return .green
        case .managedChromiumDistribution, .chromiumBrandedRuntime, .customRuntimeUnverified:
            return .orange
        }
    }

    private var preferencesTabContent: some View {
        SettingsView(
            initialTab: .general,
            visibleTabs: [.general, .appearance, .gateway]
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var taskQueueTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHero(
                    tab: .taskQueue,
                    title: L10n.SSHConnections.taskQueueTitle,
                    subtitle: L10n.SSHConnections.taskQueueSubtitle
                )

                Toggle(L10n.SSHConnections.taskQueueEnable, isOn: $heartbeatQueueEnabled)

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.SSHConnections.taskQueueHeartbeatInterval)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("5", text: $heartbeatIntervalSecondsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    Stepper(
                        L10n.SSHConnections.taskQueueMaxConcurrent(heartbeatMaxConcurrentTasks),
                        value: $heartbeatMaxConcurrentTasks,
                        in: 1...16
                    )
                    .frame(maxWidth: 260, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button(L10n.SSHConnections.taskQueueSaveSettings) {
                        persistTaskQueueSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.SSHConnections.taskQueueCancelAll) {
                        store.cancelAllQueuedHeartbeatTasks()
                        syncTaskQueueSettings()
                        queueStatusMessage = L10n.SSHConnections.taskQueueCancelledAllMessage
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.SSHConnections.taskQueueClearFinished) {
                        store.clearFinishedHeartbeatTasks()
                        syncTaskQueueSettings()
                        queueStatusMessage = L10n.SSHConnections.taskQueueClearedFinishedMessage
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.taskQueueEnqueueTitle)
                        .font(.headline)
                    TextField("codex exec \"echo heartbeat\"", text: $queueCommandInput)
                        .textFieldStyle(.roundedBorder)

                    Toggle(L10n.SSHConnections.taskQueueScheduleExecution, isOn: $queueScheduleEnabled)
                    if queueScheduleEnabled {
                        DatePicker(
                            L10n.SSHConnections.taskQueueExecuteAt,
                            selection: $queueExecuteAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    HStack(spacing: 10) {
                        Button(L10n.SSHConnections.taskQueueEnqueue) {
                            let executeAt: Date? = queueScheduleEnabled ? queueExecuteAt : nil
                            if let id = store.enqueueHeartbeatTask(command: queueCommandInput, executeAt: executeAt) {
                                queueStatusMessage = L10n.SSHConnections.taskQueueTaskAccepted(id.uuidString)
                                queueCommandInput = ""
                                syncTaskQueueSettings()
                            } else {
                                queueStatusMessage = store.lastError
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let queueStatusMessage, !queueStatusMessage.isEmpty {
                    Text(queueStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.SSHConnections.taskQueueCounts(
                        store.heartbeatQueuedCount,
                        store.heartbeatRunningCount,
                        store.heartbeatDoneCount,
                        store.heartbeatFailedCount
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    if store.heartbeatQueueTasks.isEmpty {
                        Text(L10n.SSHConnections.taskQueueEmpty)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(store.heartbeatQueueTasks.prefix(100))) { task in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(taskQueueStatusLabel(task.status))
                                            .font(.caption.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(task.executeAt.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(task.command)
                                        .font(.callout)
                                        .textSelection(.enabled)

                                    if let errorMessage = task.errorMessage, !errorMessage.isEmpty {
                                        Text(errorMessage)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }

                                    if task.status == .queued {
                                        HStack {
                                            Spacer()
                                            Button(L10n.Common.cancel) {
                                                store.cancelHeartbeatTask(task.id)
                                                syncTaskQueueSettings()
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(10)
                                .subpanelSurface()
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var todoSummaryCard: some View {
        let completedCount = todoDocument.items.filter(\.isCompleted).count
        let totalCount = todoDocument.items.count
        let percentage = Int((todoDocument.completionRate * 100).rounded())

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.SSHConnections.todoSummaryTitle)
                .font(.headline)

            Text(L10n.SSHConnections.todoSummaryProgress(completedCount, totalCount, percentage))
                .font(.title3.weight(.semibold))

            Text(L10n.SSHConnections.todoSelectedDay(AITerminalTodoSettings.dayString(from: todoSelectedDate)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .subpanelSurface()
    }

    private var todoPresentationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.SSHConnections.todoPresentationTitle)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.SSHConnections.todoSidebarPlacement)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $todoSidebarEdge) {
                    Text(L10n.SSHConnections.todoSidebarPlacementLeft)
                        .tag(AITerminalTodoSidebarEdge.leading)
                    Text(L10n.SSHConnections.todoSidebarPlacementRight)
                        .tag(AITerminalTodoSidebarEdge.trailing)
                }
                .pickerStyle(.segmented)
                .onChange(of: todoSidebarEdge) { _ in
                    persistTodoSettings(showSavedMessage: false)
                }
            }

            Toggle(L10n.SSHConnections.todoWorkspaceOverlayVisible, isOn: $todoWorkspaceOverlayVisible)
                .onChange(of: todoWorkspaceOverlayVisible) { _ in
                    persistTodoSettings(showSavedMessage: false)
                }

            if todoWorkspaceOverlayVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SSHConnections.todoWorkspaceOverlayPlacement)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $todoWorkspaceOverlayCorner) {
                        Text(L10n.SSHConnections.todoOverlayTopLeft)
                            .tag(AITerminalTodoOverlayCorner.topLeading)
                        Text(L10n.SSHConnections.todoOverlayTopRight)
                            .tag(AITerminalTodoOverlayCorner.topTrailing)
                        Text(L10n.SSHConnections.todoOverlayBottomLeft)
                            .tag(AITerminalTodoOverlayCorner.bottomLeading)
                        Text(L10n.SSHConnections.todoOverlayBottomRight)
                            .tag(AITerminalTodoOverlayCorner.bottomTrailing)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: todoWorkspaceOverlayCorner) { _ in
                        persistTodoSettings(showSavedMessage: false)
                    }
                }
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    @ViewBuilder
    private var focusedTodoWorkspaceCard: some View {
        if let target = focusedTodoWorkspaceTarget {
            let summary = store.todoWorkspaceSummary(for: target.workspaceID, on: todoSelectedDate)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.SSHConnections.todoFocusedWorkspaceTitle)
                    .font(.headline)

                Text(target.title)
                    .font(.title3.weight(.semibold))

                Text(L10n.SSHConnections.todoFocusedWorkspaceSummary(
                    summary.completedCount,
                    summary.totalCount,
                    summary.remainingCount
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(L10n.SSHConnections.todoFocusedWorkspaceHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(panelAccent.opacity(colorScheme == .dark ? 0.14 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(panelAccent.opacity(colorScheme == .dark ? 0.34 : 0.2), lineWidth: 1)
            )
        }
    }

    private var todoComposerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.SSHConnections.todoAddAction)
                .font(.headline)

            TextField(L10n.SSHConnections.todoAddTitle, text: $todoDraftTitle)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.SSHConnections.todoAddNotes, text: $todoDraftNotes)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button(L10n.SSHConnections.todoAddAction) {
                    guard let document = store.addTodoItem(
                        title: todoDraftTitle,
                        notes: todoDraftNotes,
                        for: todoSelectedDate
                    ) else {
                        todoStatusMessage = store.lastError
                        return
                    }
                    todoDocument = document
                    todoDraftTitle = ""
                    todoDraftNotes = ""
                    todoStatusMessage = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private var todoTimelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.SSHConnections.todoTimelineTitle)
                .font(.headline)

            if visibleTodoItems.isEmpty {
                Text(L10n.SSHConnections.todoEmpty)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleTodoItems, id: \.id) { item in
                        todoItemRow(item)
                    }
                }
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private func todoItemRow(_ item: AITerminalTodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    guard let document = store.setTodoItemCompleted(
                        id: item.id,
                        isCompleted: !item.isCompleted,
                        for: todoSelectedDate
                    ) else {
                        todoStatusMessage = store.lastError
                        return
                    }
                    todoDocument = document
                    todoStatusMessage = nil
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    if todoEditingItemID == item.id {
                        TextField(L10n.SSHConnections.todoAddTitle, text: $todoEditingTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField(L10n.SSHConnections.todoAddNotes, text: $todoEditingNotes)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                            .strikethrough(item.isCompleted, color: .secondary)

                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(todoTimelineLabel(for: item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    todoAssignmentMenu(for: item)
                }

                Spacer(minLength: 10)

                if todoEditingItemID == item.id {
                    Button(L10n.Common.cancel) {
                        todoEditingItemID = nil
                        todoEditingTitle = ""
                        todoEditingNotes = ""
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.SSHConnections.todoActionSave) {
                        guard let document = store.updateTodoItem(
                            id: item.id,
                            title: todoEditingTitle,
                            notes: todoEditingNotes,
                            for: todoSelectedDate
                        ) else {
                            todoStatusMessage = store.lastError
                            return
                        }
                        todoDocument = document
                        todoEditingItemID = nil
                        todoEditingTitle = ""
                        todoEditingNotes = ""
                        todoStatusMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.SSHConnections.todoActionEdit) {
                        todoEditingItemID = item.id
                        todoEditingTitle = item.title
                        todoEditingNotes = item.notes
                    }
                    .buttonStyle(.bordered)

                    if item.isCompleted {
                        Button(L10n.SSHConnections.todoActionReset) {
                            guard let document = store.setTodoItemCompleted(
                                id: item.id,
                                isCompleted: false,
                                for: todoSelectedDate
                            ) else {
                                todoStatusMessage = store.lastError
                                return
                            }
                            todoDocument = document
                            todoStatusMessage = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12)
        .subpanelSurface()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(panelAccentStrong.opacity(colorScheme == .dark ? 0.32 : 0.16))

                    Image(systemName: currentTab.systemImageName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(panelAccentSoft)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(currentTab.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text(tabSubtitle(for: currentTab))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    headerChip(
                        title: L10n.SSHConnections.tabConnections,
                        value: "\(allConnectionHosts.count)",
                        systemImage: SSHConnectionsPanelTab.connections.systemImageName
                    )
                    headerChip(
                        title: L10n.SSHConnections.taskQueueTitle,
                        value: "\(store.heartbeatQueuedCount)",
                        systemImage: SSHConnectionsPanelTab.taskQueue.systemImageName
                    )
                }
            }

            tabPicker
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func navigationButton(for tab: SSHConnectionsPanelTab) -> some View {
        let isSelected = selectedTab.wrappedValue == tab

        return Button {
            selectedTab.wrappedValue = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImageName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : panelAccent)

                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [panelAccentStrong, panelAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.32))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? panelAccent.opacity(0.5)
                            : Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.12 : 0.08),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func headerChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(panelAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }

    private func pageHero(
        tab: SSHConnectionsPanelTab,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(panelAccentStrong.opacity(colorScheme == .dark ? 0.34 : 0.14))

                Image(systemName: tab.systemImageName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(panelAccentSoft)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                panelAccentStrong.opacity(0.9),
                                GhoDexPanelPalette.accentSurfaceDark,
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
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }

    private func tabSubtitle(for tab: SSHConnectionsPanelTab) -> String {
        switch tab {
        case .connections:
            return L10n.SSHConnections.connectionsPageSubtitle
        case .todo:
            return L10n.SSHConnections.todoSubtitle
        case .learning:
            return L10n.SSHConnections.learningSubtitle
        case .taskQueue:
            return L10n.SSHConnections.taskQueueSubtitle
        case .browser:
            return L10n.Settings.browserDescription
        case .preferences:
            return L10n.Settings.sidebarDescription
        }
    }

    private var managedSkillRepositoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.SSHConnections.learningSkillReposTitle)
                        .font(.headline)
                    Text(L10n.SSHConnections.learningSkillReposSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(L10n.SSHConnections.learningSkillReposCheckUpdates) {
                    checkManagedSkillRepositories()
                }
                .buttonStyle(.bordered)
                .disabled(learningOperationInProgress)

                Button(L10n.SSHConnections.learningSkillReposPullUpdates) {
                    syncManagedSkillRepositories()
                }
                .buttonStyle(.borderedProminent)
                .disabled(learningOperationInProgress)
            }

            if managedSkillStatuses.isEmpty {
                Text(L10n.SSHConnections.learningSkillReposEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(managedSkillStatuses) { status in
                        managedSkillRepositoryRow(status)
                    }
                }
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private func managedSkillRepositoryRow(
        _ status: AITerminalManagerStore.ManagedSkillRepositoryStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.skillName)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 8)

                Text(skillStatusLabel(status.state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(skillStatusColor(status.state))
            }

            Text("\(status.repositoryURL) @ \(status.branch)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let commitLine = managedSkillCommitLine(status), !commitLine.isEmpty {
                Text(commitLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(status.destinationPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let message = status.message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .subpanelSurface()
    }

    private func skillStatusLabel(_ state: AITerminalManagerStore.ManagedSkillRepositoryState) -> String {
        switch state {
        case .latest:
            return L10n.SSHConnections.learningSkillReposStatusLatest
        case .updateAvailable:
            return L10n.SSHConnections.learningSkillReposStatusUpdateAvailable
        case .notInstalled:
            return L10n.SSHConnections.learningSkillReposStatusNotInstalled
        case .localChanges:
            return L10n.SSHConnections.learningSkillReposStatusLocalChanges
        case .error:
            return L10n.SSHConnections.learningSkillReposStatusError
        }
    }

    private func managedSkillCommitLine(
        _ status: AITerminalManagerStore.ManagedSkillRepositoryStatus
    ) -> String? {
        guard let localCommit = status.localCommit, !localCommit.isEmpty else { return nil }

        var parts: [String] = ["local: \(localCommit)"]
        if let remoteCommit = status.remoteCommit, !remoteCommit.isEmpty {
            parts.append("remote: \(remoteCommit)")
        }
        if let expectedTag = status.expectedTag, !expectedTag.isEmpty {
            parts.append("tag: \(expectedTag)")
        }
        if let expectedCommit = status.expectedCommit, !expectedCommit.isEmpty {
            parts.append("expected: \(expectedCommit)")
        }
        return parts.joined(separator: "  ")
    }

    private func skillStatusColor(_ state: AITerminalManagerStore.ManagedSkillRepositoryState) -> Color {
        switch state {
        case .latest:
            return .green
        case .updateAvailable, .localChanges:
            return .orange
        case .notInstalled:
            return .secondary
        case .error:
            return .red
        }
    }

    private var learningLogPanel: some View {
        let entries = learningLogEntries
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.SSHConnections.learningLogPanelTitle)
                        .font(.headline)

                    Text(L10n.SSHConnections.learningLogPanelSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if !entries.isEmpty {
                    Button(L10n.SSHConnections.learningLogClear) {
                        store.clearLearningLogs()
                        expandedLearningLogIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if entries.isEmpty {
                Text(L10n.SSHConnections.learningLogEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entries.prefix(40))) { entry in
                        learningLogRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private func learningLogRow(_ entry: AITerminalLearningLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.status == .success ? .green : .red)

                Spacer(minLength: 8)

                Text(Self.learningLogDateFormatter.string(from: entry.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.outputSummary)
                .font(.callout)
                .foregroundStyle(.primary)

            if let exitCode = entry.exitCode {
                Text(L10n.SSHConnections.learningLogExitCode(exitCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let outputDetail = entry.outputDetail, !outputDetail.isEmpty {
                let isExpanded = expandedLearningLogIDs.contains(entry.id)
                Button(isExpanded ? L10n.SSHConnections.learningLogHideDetails : L10n.SSHConnections.learningLogShowDetails) {
                    if isExpanded {
                        expandedLearningLogIDs.remove(entry.id)
                    } else {
                        expandedLearningLogIDs.insert(entry.id)
                    }
                }
                .buttonStyle(.link)

                if isExpanded {
                    Text(outputDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !entry.notesAbsolutePath.isEmpty {
                Text(entry.notesAbsolutePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .subpanelSurface()
    }

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button(L10n.SSHConnections.newConnection) {
                    prepareNewConnection()
                }

                Button(L10n.AITerminalManager.reloadSSHConfig) {
                    store.reloadImportedSSHHosts()
                }
            }

            TextField(L10n.SSHConnections.searchConnections, text: $hostSearchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if displayFavoriteHosts.isEmpty &&
                        displayRecentHosts.isEmpty &&
                        displaySavedHosts.isEmpty &&
                        displayImportedHosts.isEmpty &&
                        displaySavedWorkspaceTemplates.isEmpty {
                        emptySidebarState
                    } else {
                        if !displayFavoriteHosts.isEmpty {
                            connectionsSection(
                                title: L10n.AITerminalManager.favoriteHosts,
                                hosts: displayFavoriteHosts
                            )
                        }

                        if !displayRecentHosts.isEmpty {
                            recentConnectionsSection
                        }

                        if !displaySavedHosts.isEmpty {
                            connectionsSection(
                                title: L10n.AITerminalManager.savedHosts,
                                hosts: displaySavedHosts
                            )
                        }

                        if !displayImportedHosts.isEmpty {
                            connectionsSection(
                                title: L10n.AITerminalManager.importedHosts,
                                hosts: displayImportedHosts
                            )
                        }

                        if !displaySavedWorkspaceTemplates.isEmpty {
                            savedWorkspacesSection
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
        }
        .padding(18)
        .panelSurface()
    }

    private var emptySidebarState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.AITerminalManager.hostsEmpty)
                .foregroundStyle(.secondary)

            Button(L10n.SSHConnections.newConnection) {
                prepareNewConnection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .subpanelSurface()
    }

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L10n.AITerminalManager.recentHosts)

            VStack(spacing: 10) {
                ForEach(displayRecentHosts) { host in
                    recentHostRow(host)
                }
            }
        }
    }

    private func connectionsSection(title: String, hosts: [AITerminalHost]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)

            VStack(spacing: 8) {
                ForEach(hosts) { host in
                    sidebarHostRow(host)
                }
            }
        }
    }

    private var savedWorkspacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L10n.AITerminalManager.savedWorkspacesSection)

            VStack(spacing: 8) {
                ForEach(displaySavedWorkspaceTemplates) { workspace in
                    savedWorkspaceRow(workspace)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func recentHostRow(_ host: AITerminalHost) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(host.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if store.isFavorite(host) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(panelAccent)
                    }

                    if let recentRecord = store.recentRecord(for: host) {
                        statusPill(for: recentRecord)
                    }
                }

                Text(primarySubtitle(for: host))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let recentRecord = store.recentRecord(for: host) {
                    Text(recentTimestamp(for: recentRecord))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.open(host: host)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelAccent)
        }
        .padding(14)
        .background(rowBackground(for: host), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(rowBorder(for: host), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            selectedHostID = host.id
        }
    }

    private func sidebarHostRow(_ host: AITerminalHost) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(host.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if store.isFavorite(host) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(panelAccent)
                    }

                    if hasActiveSession(for: host) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .foregroundStyle(panelAccent)
                    }
                }

                Text(primarySubtitle(for: host))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    compactBadge(hostSourceLabel(for: host))

                    if host.transport == .ssh, host.authMode == .password {
                        compactBadge(host.authMode.displayName)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(rowBackground(for: host), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(rowBorder(for: host), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            selectedHostID = host.id
        }
    }

    private func savedWorkspaceRow(_ workspace: AITerminalSavedWorkspaceTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(workspace.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(savedWorkspaceSummary(for: workspace))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(workspace.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                store.open(savedWorkspaceTemplate: workspace)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelAccent)
            .help(L10n.AITerminalManager.launch)

            Button(role: .destructive) {
                store.removeSavedWorkspaceTemplate(workspace)
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help(L10n.AITerminalManager.remove)
        }
        .padding(14)
        .background(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.18 : 0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            store.open(savedWorkspaceTemplate: workspace)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedHost {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroSection(for: selectedHost)
                    summaryGrid(for: selectedHost)
                    if selectedHost.transport == .ssh {
                        sessionsSection(for: selectedHost)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .panelSurface()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.SSHConnections.connectionsPageTitle)
                    .font(.title2.weight(.semibold))

                Text(allConnectionHosts.isEmpty ? L10n.AITerminalManager.hostsEmpty : L10n.AITerminalManager.noHostSelected)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(L10n.SSHConnections.newConnection) {
                        prepareNewConnection()
                    }

                    Button(L10n.AITerminalManager.reloadSSHConfig) {
                        store.reloadImportedSSHHosts()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(32)
            .panelSurface()
        }
    }

    private func heroSection(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(host.name)
                        .font(.system(size: 30, weight: .semibold))

                    Text(primarySubtitle(for: host))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        compactBadge(hostSourceLabel(for: host))

                        if host.transport == .ssh {
                            compactBadge(host.authMode.displayName)
                        }

                        if hasActiveSession(for: host) {
                            compactBadge(L10n.SSHConnections.activeSessions)
                        }
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 10) {
                    Button(L10n.AITerminalManager.connect) {
                        store.open(host: host)
                    }
                    .controlSize(.large)

                    HStack(spacing: 8) {
                        Button(store.isFavorite(host) ? L10n.AITerminalManager.removeFavoriteHost : L10n.AITerminalManager.favoriteHost) {
                            store.toggleFavorite(host)
                        }

                        Button(L10n.AITerminalManager.edit) {
                            beginEditing(host)
                        }

                        Button(L10n.AITerminalManager.duplicateHost) {
                            beginDuplicating(host)
                        }
                    }
                }
            }

            if let recentRecord = store.recentRecord(for: host) {
                HStack(spacing: 8) {
                    statusPill(for: recentRecord)

                    Text(recentSummary(for: recentRecord))
                        .font(.callout)
                        .foregroundStyle(recentRecord.status == .failed ? .red : .secondary)
                }
            }

            if host.transport == .ssh, host.authMode == .password {
                Text(store.hasStoredPassword(for: host) ? L10n.SSHConnections.passwordStored : L10n.SSHConnections.passwordNotStored)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if store.isUserManagedHost(host) {
                    Button(L10n.AITerminalManager.remove, role: .destructive) {
                        store.removeHost(host)
                    }
                } else if store.isImportedHostOverridden(host) {
                    Button(L10n.AITerminalManager.resetOverride, role: .destructive) {
                        store.resetImportedHostOverride(host)
                    }
                }
            }
        }
        .padding(20)
        .subpanelSurface()
    }

    private func summaryGrid(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L10n.AITerminalManager.hostDetails)

            switch host.transport {
            case .ssh:
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220), spacing: 14),
                        GridItem(.flexible(minimum: 220), spacing: 14),
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    detailCell(label: L10n.AITerminalManager.displayName, value: host.name)
                    detailCell(label: L10n.AITerminalManager.hostTarget, value: host.connectionTarget ?? "—")
                    detailCell(label: L10n.AITerminalManager.hostname, value: host.hostname ?? "—")
                    detailCell(label: L10n.AITerminalManager.user, value: host.user ?? "—")
                    detailCell(label: L10n.AITerminalManager.port, value: host.port.map(String.init) ?? "—")
                    detailCell(label: L10n.AITerminalManager.defaultDirectory, value: host.defaultDirectory ?? "—")
                    detailCell(label: L10n.SSHConnections.authentication, value: host.authMode.displayName)
                    detailCell(label: L10n.AITerminalManager.hostSource, value: hostSourceLabel(for: host))
                }

            case .localmcd:
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220), spacing: 14),
                        GridItem(.flexible(minimum: 220), spacing: 14),
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    detailCell(label: L10n.AITerminalManager.displayName, value: host.name)
                    detailCell(label: L10n.SSHConnections.connectionType, value: L10n.SSHConnections.connectionTypeLocalMCD)
                    detailCell(label: L10n.AITerminalManager.defaultDirectory, value: host.defaultDirectory ?? "—")
                    detailCell(label: L10n.AITerminalManager.hostSource, value: hostSourceLabel(for: host))
                    detailCell(
                        label: L10n.SSHConnections.localMCDStartupCommands,
                        value: host.startupCommands.isEmpty ? "—" : host.startupCommands.joined(separator: "\n")
                    )
                }

            case .local:
                EmptyView()
            }
        }
    }

    private func sessionsSection(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L10n.SSHConnections.activeSessions)

            if contextualRemoteSessions(for: host).isEmpty {
                Text(L10n.SSHConnections.activeSessionsEmpty)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .subpanelSurface()
            } else {
                VStack(spacing: 12) {
                    ForEach(contextualRemoteSessions(for: host)) { session in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                    Text(session.hostTarget)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 10)

                                if session.isFocused {
                                    compactBadge(L10n.AITerminalManager.focused)
                                }
                            }

                            if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
                                Text(workingDirectory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Text(session.authState.displayName)
                                .font(.caption)
                                .foregroundStyle(authStateColor(session.authState))

                            HStack(spacing: 10) {
                                Button(L10n.AITerminalManager.focus) {
                                    store.focus(sessionID: session.id)
                                }

                                Button(L10n.SSHConnections.reconnect) {
                                    reconnect(session: session)
                                }
                            }
                        }
                        .padding(16)
                        .subpanelSurface()
                    }
                }
            }
        }
    }

    private var hostEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.SSHConnections.connectionType, selection: $hostEditorType) {
                        ForEach(ConnectionEditorType.allCases) { connectionType in
                            Text(connectionType.displayName).tag(connectionType)
                        }
                    }
                    .disabled(editingHostID != nil)
                }

                switch hostEditorType {
                case .ssh:
                    Section {
                        TextField(L10n.AITerminalManager.displayName, text: $hostName)
                        TextField(L10n.AITerminalManager.sshAlias, text: $hostAlias)
                        TextField(L10n.AITerminalManager.hostname, text: $hostHostname)
                        TextField(L10n.AITerminalManager.user, text: $hostUser)
                        TextField(L10n.AITerminalManager.port, text: $hostPort)
                        TextField(L10n.AITerminalManager.defaultDirectory, text: $hostDefaultDirectory)
                    }

                    Section(L10n.SSHConnections.authentication) {
                        Picker(L10n.SSHConnections.authentication, selection: $hostAuthMode) {
                            ForEach(AITerminalHostAuthMode.allCases) { authMode in
                                Text(authMode.displayName).tag(authMode)
                            }
                        }

                        if hostAuthMode == .password {
                            SecureField(L10n.SSHConnections.password, text: $hostPassword)

                            Text(passwordHelperText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                case .localmcd:
                    Section {
                        TextField(L10n.AITerminalManager.displayName, text: $hostName)
                        TextField(L10n.AITerminalManager.defaultDirectory, text: $hostDefaultDirectory)
                    }

                    Section(L10n.SSHConnections.localMCDStartupCommands) {
                        TextEditor(text: $hostStartupCommands)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 160)

                        Text(L10n.SSHConnections.localMCDStartupCommandsHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(hostEditorTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.AITerminalManager.cancelEdit) {
                        cancelEditor()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(editingHostID == nil ? L10n.SSHConnections.saveConnection : L10n.SSHConnections.updateConnection) {
                        persistEditor()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.18), lineWidth: 1)
            )
    }

    private func detailCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subpanelSurface()
    }

    private func compactBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.6), in: Capsule())
    }

    private func statusPill(for recentRecord: AITerminalRecentHostRecord) -> some View {
        Text(recentStatusTitle(for: recentRecord))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(recentRecord.status == .failed ? .red : panelAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (recentRecord.status == .failed ? Color.red : panelAccent).opacity(0.12),
                in: Capsule()
            )
    }

    private func rowBackground(for host: AITerminalHost) -> Color {
        if selectedHostID == host.id {
            return panelAccent.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }

        return Color.white.opacity(colorScheme == .dark ? 0.035 : 0.55)
    }

    private func rowBorder(for host: AITerminalHost) -> Color {
        if selectedHostID == host.id {
            return panelAccent.opacity(colorScheme == .dark ? 0.32 : 0.2)
        }

        return Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.18 : 0.1)
    }

    private func authStateColor(_ authState: AITerminalSSHSessionAuthState) -> Color {
        switch authState {
        case .failed:
            .red
        case .connected:
            .green
        case .authenticating, .awaitingPassword, .connecting:
            .secondary
        }
    }

    private func beginEditing(_ host: AITerminalHost) {
        selectedHostID = host.id
        editingHostID = host.id
        hostEditorType = .init(host.transport)
        hostName = host.name
        hostAlias = host.sshAlias ?? ""
        hostHostname = host.hostname ?? ""
        hostUser = host.user ?? ""
        hostPort = host.port.map(String.init) ?? ""
        hostDefaultDirectory = host.defaultDirectory ?? ""
        hostStartupCommands = host.startupCommands.joined(separator: "\n")
        hostAuthMode = host.authMode
        hostPassword = ""
        isPresentingEditor = true
    }

    private func beginDuplicating(_ host: AITerminalHost) {
        selectedHostID = host.id
        editingHostID = nil
        hostEditorType = .init(host.transport)
        hostName = "\(host.name) \(L10n.AITerminalManager.copySuffix)"
        hostDefaultDirectory = host.defaultDirectory ?? ""
        hostStartupCommands = host.startupCommands.joined(separator: "\n")
        hostAuthMode = host.authMode

        if host.transport == .ssh {
            hostAlias = AITerminalManagerStore.duplicateAlias(
                for: host,
                existingHosts: allConnectionHosts
            )
            hostHostname = host.hostname ?? ""
            hostUser = host.user ?? ""
            hostPort = host.port.map(String.init) ?? ""
        } else {
            hostAlias = ""
            hostHostname = ""
            hostUser = ""
            hostPort = ""
        }

        hostPassword = ""
        isPresentingEditor = true
    }

    private func prepareNewConnection() {
        hostEditorType = .ssh
        editingHostID = nil
        hostName = ""
        hostAlias = ""
        hostHostname = ""
        hostUser = ""
        hostPort = ""
        hostDefaultDirectory = ""
        hostStartupCommands = ""
        hostAuthMode = .system
        hostPassword = ""
        isPresentingEditor = true
    }

    private func cancelEditor() {
        isPresentingEditor = false
        hostPassword = ""
        hostStartupCommands = ""
        editingHostID = nil
    }

    private func persistEditor() {
        let draftHostID: String
        switch hostEditorType {
        case .ssh:
            draftHostID = AITerminalHost.stableID(
                existingID: editingHostID,
                sshAlias: hostAlias,
                hostname: hostHostname,
                user: hostUser
            )

            store.saveHost(
                existingHostID: editingHostID,
                name: hostName,
                sshAlias: hostAlias,
                hostname: hostHostname,
                user: hostUser,
                port: hostPort,
                defaultDirectory: hostDefaultDirectory,
                authMode: hostAuthMode,
                password: hostPassword
            )

        case .localmcd:
            draftHostID = editingHostID ?? "localmcd:\(UUID().uuidString)"
            store.saveLocalMCDHost(
                existingHostID: draftHostID,
                name: hostName,
                defaultDirectory: hostDefaultDirectory,
                startupCommands: hostStartupCommands
            )
        }

        guard store.lastError == nil else { return }
        selectedHostID = draftHostID
        cancelEditor()
    }

    private func reconnect(session: AITerminalRemoteSessionSummary) {
        guard let host = store.availableHosts.first(where: { $0.id == session.hostID }) else { return }
        store.open(host: host)
    }

    private func syncSelection() {
        let ids = Set(allConnectionHosts.map(\.id))

        if let selectedHostID, ids.contains(selectedHostID) {
            return
        }

        if let firstHostID = allConnectionHosts.first?.id {
            selectedHostID = firstHostID
            return
        }

        selectedSavedWorkspaceID = displaySavedWorkspaceTemplates.first?.id
    }

    private func resolvedDirectoryOverride(
        _ candidate: String,
        fallback: String
    ) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private func chooseDirectory(currentPath: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: NSString(string: trimmed).expandingTildeInPath,
                isDirectory: true
            )
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func syncTodoSettings() {
        let settings = store.todoSettings
        todoEnabled = settings.enabled
        todoShowCompletedItems = settings.showCompletedItems
        todoSelectedDate = AITerminalTodoSettings.date(fromDayString: settings.selectedDateAnchor) ?? .now
        todoSidebarEdge = settings.sidebarEdge
        todoWorkspaceOverlayVisible = settings.workspaceOverlayVisible
        todoWorkspaceOverlayCorner = settings.workspaceOverlayCorner
        refreshTodoDocument()
        if todoStatusMessage == L10n.SSHConnections.todoSaved {
            todoStatusMessage = nil
        }
    }

    private func refreshTodoDocument() {
        todoDocument = store.todoDocument(for: todoSelectedDate)
    }

    private func persistTodoDateSelection() {
        persistTodoSettings(showSavedMessage: false)
        refreshTodoDocument()
    }

    private func persistTodoSettings(showSavedMessage: Bool) {
        let nextTodoSettings = AITerminalTodoSettings(
            enabled: todoEnabled,
            workspaceRootPath: resolvedTodoWorkspacePath,
            showCompletedItems: todoShowCompletedItems,
            selectedDateAnchor: AITerminalTodoSettings.dayString(from: todoSelectedDate),
            sidebarEdge: todoSidebarEdge,
            workspaceOverlayVisible: todoWorkspaceOverlayVisible,
            workspaceOverlayCorner: todoWorkspaceOverlayCorner
        )

        if persistSharedWorkspacePathSettings(todoSettings: nextTodoSettings) {
            todoWorkspaceRootPath = resolvedTodoWorkspacePath
            todoStatusMessage = showSavedMessage ? L10n.SSHConnections.todoSaved : nil
        } else {
            todoStatusMessage = store.lastError ?? browserErrorMessage
        }
    }

    private func initializeTodoWorkspace() {
        guard let result = store.initializeTodoWorkspace(rootPath: resolvedTodoWorkspacePath) else {
            todoStatusMessage = L10n.SSHConnections.todoInitializeFailedMessage(
                store.lastError ?? "unknown"
            )
            return
        }

        todoWorkspaceRootPath = result.workspaceRootPath
        todoStatusMessage = L10n.SSHConnections.todoInitializedMessage(
            result.createdFileCount,
            result.reusedFileCount
        )
        refreshTodoDocument()
    }

    private func syncLearningSettings() {
        let settings = store.learningSettings
        learningEnabled = settings.enabled
        learningCommandTemplate = settings.commandTemplate
        managedSkillStatuses = store.managedSkillStatuses
        if !learningOperationInProgress {
            learningStatusMessage = nil
        }
    }

    private func syncTaskQueueSettings() {
        let settings = store.heartbeatQueueSettings
        heartbeatQueueEnabled = settings.enabled
        heartbeatIntervalSecondsText = String(format: "%.3f", settings.heartbeatIntervalSeconds)
        heartbeatMaxConcurrentTasks = settings.maxConcurrentTasks
        queueStatusMessage = nil
    }

    private func syncWorkspacePathSettings() {
        let learningSettings = store.learningSettings
        let currentChatWorkspacePath = AITerminalLearningSettings.chatWorkspacePath(
            fromLearnWorkspacePath: learningSettings.defaultProjectPath
        )
        let todoSettings = store.todoSettings
        let currentProfilePath = appDelegate.browserProfilePathOverride ?? ""
        let currentRuntimePath = appDelegate.browserRuntimePathOverride ?? ""

        let inferredWorkspaceRoot = AITerminalWorkspaceDefaults.inferWorkspaceRootPath(
            chatWorkspacePath: currentChatWorkspacePath,
            todoWorkspacePath: todoSettings.workspaceRootPath,
            browserProfilePath: currentProfilePath,
            browserRuntimePath: currentRuntimePath
        ) ?? AITerminalWorkspaceDefaults.defaultWorkspaceRootPath

        let effectiveChatPath = currentChatWorkspacePath.isEmpty
            ? AITerminalWorkspaceDefaults.chatWorkspacePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentChatWorkspacePath
        let effectiveTodoPath = todoSettings.workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AITerminalWorkspaceDefaults.todoWorkspacePath(workspaceRootPath: inferredWorkspaceRoot)
            : todoSettings.workspaceRootPath
        let effectiveProfilePath = currentProfilePath.isEmpty
            ? AITerminalWorkspaceDefaults.browserProfilePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentProfilePath
        let effectiveRuntimePath = currentRuntimePath.isEmpty
            ? AITerminalWorkspaceDefaults.browserRuntimePath(workspaceRootPath: inferredWorkspaceRoot)
            : currentRuntimePath

        workspaceRootPathText = inferredWorkspaceRoot
        learningChatWorkspacePath = effectiveChatPath
        learningNotesRelativePath = learningSettings.notesRelativePath
        todoWorkspaceRootPath = effectiveTodoPath
        browserProfilePathText = effectiveProfilePath
        browserRuntimePathText = effectiveRuntimePath
        showAdvancedWorkspacePaths = !AITerminalWorkspaceDefaults.usesDefaultWorkspaceLayout(
            workspaceRootPath: inferredWorkspaceRoot,
            chatWorkspacePath: effectiveChatPath,
            notesRelativePath: learningSettings.notesRelativePath,
            todoWorkspacePath: effectiveTodoPath,
            browserProfilePath: effectiveProfilePath,
            browserRuntimePath: effectiveRuntimePath
        )
        browserSaveMessage = nil
        browserErrorMessage = nil
    }

    private func persistSharedWorkspacePathSettings(
        learningSettings: AITerminalLearningSettings? = nil,
        todoSettings: AITerminalTodoSettings? = nil
    ) -> Bool {
        let nextLearningSettings = learningSettings ?? store.learningSettings
        let nextTodoSettings = todoSettings ?? store.todoSettings

        do {
            try appDelegate.saveBrowserSettings(
                profilePath: resolvedBrowserProfilePath,
                runtimePath: resolvedBrowserRuntimePath
            )
        } catch {
            browserErrorMessage = error.localizedDescription
            browserSaveMessage = nil
            return false
        }

        store.saveLearningSettings(.init(
            enabled: nextLearningSettings.enabled,
            preferTabWorkingDirectory: nextLearningSettings.preferTabWorkingDirectory,
            defaultProjectPath: resolvedLearnWorkspacePath,
            notesRelativePath: resolvedNotesRelativePath,
            commandTemplate: nextLearningSettings.commandTemplate,
            fastModel: nextLearningSettings.fastModel,
            promptTemplate: nextLearningSettings.promptTemplate
        ))
        if let error = store.lastError {
            learningStatusMessage = error
            return false
        }

        store.saveTodoSettings(.init(
            enabled: nextTodoSettings.enabled,
            workspaceRootPath: resolvedTodoWorkspacePath,
            showCompletedItems: nextTodoSettings.showCompletedItems,
            selectedDateAnchor: nextTodoSettings.selectedDateAnchor,
            sidebarEdge: nextTodoSettings.sidebarEdge,
            workspaceOverlayVisible: nextTodoSettings.workspaceOverlayVisible,
            workspaceOverlayCorner: nextTodoSettings.workspaceOverlayCorner
        ))
        if let error = store.lastError {
            todoStatusMessage = error
            return false
        }

        browserErrorMessage = nil
        syncWorkspacePathSettings()
        return true
    }

    private func persistTaskQueueSettings() {
        let trimmedInterval = heartbeatIntervalSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedInterval = Double(trimmedInterval) ?? store.heartbeatQueueSettings.heartbeatIntervalSeconds
        store.saveHeartbeatQueueSettings(.init(
            enabled: heartbeatQueueEnabled,
            heartbeatIntervalSeconds: parsedInterval,
            maxConcurrentTasks: heartbeatMaxConcurrentTasks
        ))
        syncTaskQueueSettings()
        queueStatusMessage = store.lastError ?? L10n.SSHConnections.taskQueueSaved
    }

    private func persistBrowserSettings() {
        if persistSharedWorkspacePathSettings() {
            browserSaveMessage = L10n.Settings.browserSaved
            browserErrorMessage = nil
        } else {
            browserSaveMessage = nil
        }
    }

    private func taskQueueStatusLabel(_ status: AITerminalHeartbeatTaskStatus) -> String {
        switch status {
        case .queued:
            return L10n.SSHConnections.taskQueueStatusQueued
        case .running:
            return L10n.SSHConnections.taskQueueStatusRunning
        case .done:
            return L10n.SSHConnections.taskQueueStatusDone
        case .failed:
            return L10n.SSHConnections.taskQueueStatusFailed
        case .cancelled:
            return L10n.SSHConnections.taskQueueStatusCancelled
        }
    }

    private func persistLearningSettings() {
        let current = store.learningSettings
        let nextLearningSettings = AITerminalLearningSettings(
            enabled: learningEnabled,
            preferTabWorkingDirectory: current.preferTabWorkingDirectory,
            defaultProjectPath: resolvedLearnWorkspacePath,
            notesRelativePath: resolvedNotesRelativePath,
            commandTemplate: learningCommandTemplate,
            fastModel: current.fastModel,
            promptTemplate: current.promptTemplate
        )

        if persistSharedWorkspacePathSettings(
            learningSettings: nextLearningSettings,
            todoSettings: store.todoSettings
        ) {
            learningChatWorkspacePath = resolvedLearningChatWorkspacePath
            learningStatusMessage = L10n.SSHConnections.learningSaved
        } else {
            learningStatusMessage = store.lastError ?? browserErrorMessage
        }
    }

    private func requestInitializeLearningWorkspace() {
        guard !learningOperationInProgress else { return }
        guard let resolvedChatWorkspacePath = validatedLearningChatWorkspacePath() else {
            return
        }
        initializeChatWorkspaceCandidate = resolvedChatWorkspacePath
        showingInitializeConfirmation = true
    }

    private func confirmInitializeLearningWorkspace() {
        learningChatWorkspacePath = initializeChatWorkspaceCandidate
        initializeLearningWorkspace()
    }

    private func initializeLearningWorkspace() {
        guard !learningOperationInProgress else { return }
        guard let resolvedChatWorkspacePath = validatedLearningChatWorkspacePath() else {
            return
        }
        let resolvedCommandTemplate = learningCommandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AITerminalLearningSettings.defaultCommandTemplate
            : learningCommandTemplate

        learningOperationInProgress = true
        learningStatusMessage = L10n.SSHConnections.learningInitializing
        Task { @MainActor in
            defer { learningOperationInProgress = false }
            guard let result = await store.initializeChatAndLearnWorkspaceAsync(
                chatWorkspacePath: resolvedChatWorkspacePath,
                commandTemplate: resolvedCommandTemplate
            ) else {
                learningStatusMessage = L10n.SSHConnections.learningInitializeFailedMessage(
                    store.lastError ?? "unknown"
                )
                return
            }

            learningChatWorkspacePath = result.chatWorkspacePath
            learningCommandTemplate = resolvedCommandTemplate
            managedSkillStatuses = store.managedSkillStatuses
            let skillErrors = managedSkillStatuses.filter { $0.state == .error }.count
            learningStatusMessage = if skillErrors == 0 {
                L10n.SSHConnections.learningInitializedMessage(
                    result.createdFileCount,
                    result.reusedFileCount
                )
            } else {
                L10n.SSHConnections.learningInitializedWithSkillSyncWarningMessage(
                    result.createdFileCount,
                    result.reusedFileCount,
                    skillErrors
                )
            }
        }
    }

    private func checkManagedSkillRepositories() {
        guard !learningOperationInProgress else { return }
        guard let resolvedChatWorkspacePath = validatedLearningChatWorkspacePath() else {
            return
        }

        learningOperationInProgress = true
        learningStatusMessage = L10n.SSHConnections.learningSkillReposChecking
        Task { @MainActor in
            defer { learningOperationInProgress = false }
            managedSkillStatuses = await store.checkManagedSkillRepositoryUpdatesAsync(
                chatWorkspacePath: resolvedChatWorkspacePath
            )
            let latestCount = managedSkillStatuses.filter { $0.state == .latest }.count
            let updateCount = managedSkillStatuses.filter { $0.state == .updateAvailable }.count
            let errorCount = managedSkillStatuses.filter { $0.state == .error }.count
            learningStatusMessage = L10n.SSHConnections.learningSkillReposCheckedMessage(
                latestCount,
                updateCount,
                errorCount
            )
        }
    }

    private func syncManagedSkillRepositories() {
        guard !learningOperationInProgress else { return }
        guard let resolvedChatWorkspacePath = validatedLearningChatWorkspacePath() else {
            return
        }

        learningOperationInProgress = true
        learningStatusMessage = L10n.SSHConnections.learningSkillReposPulling
        Task { @MainActor in
            defer { learningOperationInProgress = false }
            managedSkillStatuses = await store.syncManagedSkillRepositoriesAsync(
                chatWorkspacePath: resolvedChatWorkspacePath
            )
            let latestCount = managedSkillStatuses.filter { $0.state == .latest }.count
            let updateCount = managedSkillStatuses.filter { $0.state == .updateAvailable }.count
            let errorCount = managedSkillStatuses.filter { $0.state == .error }.count
            learningStatusMessage = L10n.SSHConnections.learningSkillReposPulledMessage(
                latestCount,
                updateCount,
                errorCount
            )
        }
    }

    private func validatedLearningChatWorkspacePath() -> String? {
        let trimmedChatWorkspacePath = resolvedLearningChatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatWorkspacePath.isEmpty else {
            learningStatusMessage = L10n.SSHConnections.learningChatWorkspaceRequired
            return nil
        }
        return trimmedChatWorkspacePath
    }

    private var selectedTodoDayFilePath: String {
        let trimmedRootPath = resolvedTodoWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRootPath.isEmpty else {
            return "-"
        }
        return AITerminalTodoSettings(
            enabled: todoEnabled,
            workspaceRootPath: trimmedRootPath,
            showCompletedItems: todoShowCompletedItems,
            selectedDateAnchor: AITerminalTodoSettings.dayString(from: todoSelectedDate),
            sidebarEdge: todoSidebarEdge,
            workspaceOverlayVisible: todoWorkspaceOverlayVisible,
            workspaceOverlayCorner: todoWorkspaceOverlayCorner
        ).dayFilePath(for: todoSelectedDate)
    }

    private var visibleTodoItems: [AITerminalTodoItem] {
        let ordered = todoDocument.orderedItems
        guard !todoShowCompletedItems else { return ordered }
        return ordered.filter { !$0.isCompleted }
    }

    private func todoAssignmentMenu(for item: AITerminalTodoItem) -> some View {
        Menu {
            Button(L10n.SSHConnections.todoAssignmentClear) {
                assignTodoItem(item.id, to: nil)
            }

            if todoWorkspaceTargets.isEmpty {
                Text(L10n.SSHConnections.todoAssignmentNoTabs)
            } else {
                ForEach(todoWorkspaceTargets) { target in
                    Button(target.title) {
                        assignTodoItem(item.id, to: target.workspaceID)
                    }
                }
            }
        } label: {
            Label(todoAssignmentTitle(for: item), systemImage: "rectangle.stack.badge.person.crop")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
    }

    private func todoAssignmentTitle(for item: AITerminalTodoItem) -> String {
        guard let workspaceID = item.assignedWorkspaceID else {
            return L10n.SSHConnections.todoAssignmentUnassigned
        }
        return todoWorkspaceTargets.first(where: { $0.workspaceID == workspaceID })?.title
            ?? L10n.SSHConnections.todoAssignmentUnavailable
    }

    private func todoTimelineLabel(for item: AITerminalTodoItem) -> String {
        let created = Self.todoTimelineTimeFormatter.string(from: item.createdAt)
        if let completedAt = item.completedAt {
            let completed = Self.todoTimelineTimeFormatter.string(from: completedAt)
            return "Created \(created) · Completed \(completed)"
        }
        return "Created \(created)"
    }

    private func assignTodoItem(_ id: UUID, to workspaceID: UUID?) {
        guard let document = store.assignTodoItem(id: id, to: workspaceID, for: todoSelectedDate) else {
            todoStatusMessage = store.lastError
            return
        }
        todoDocument = document
        todoStatusMessage = nil
    }

    private var displayRecentHosts: [AITerminalHost] {
        Self.sidebarRecentHosts(
            recentHosts: filterHosts(store.recentHosts),
            favoriteHosts: displayFavoriteHosts
        )
    }

    private var displayFavoriteHosts: [AITerminalHost] {
        Self.sidebarFavoriteHosts(
            favoriteHosts: filterHosts(store.favoriteHosts)
        )
    }

    private var displaySavedHosts: [AITerminalHost] {
        Self.sidebarSavedHosts(
            savedHosts: filterHosts(store.savedHosts),
            favoriteHosts: displayFavoriteHosts,
            recentHosts: displayRecentHosts
        )
    }

    private var displayImportedHosts: [AITerminalHost] {
        Self.sidebarImportedHosts(
            importedHosts: filterHosts(store.mergedImportedHosts),
            favoriteHosts: displayFavoriteHosts,
            savedHosts: filterHosts(store.savedHosts),
            recentHosts: displayRecentHosts
        )
    }

    private var displaySavedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate] {
        filterSavedWorkspaceTemplates(store.savedWorkspaceTemplates)
    }

    private var allConnectionHosts: [AITerminalHost] {
        store.availableHosts.filter { !$0.isLocal }
    }

    private var hostEditorTitle: String {
        if editingHostID == nil {
            return L10n.SSHConnections.newConnection
        }

        switch hostEditorType {
        case .ssh:
            return L10n.AITerminalManager.editSSHHost
        case .localmcd:
            return L10n.SSHConnections.editLocalMCDConnection
        }
    }

    private var passwordHelperText: String {
        if hostEditorType != .ssh || hostAuthMode != .password {
            return ""
        }

        if let editingHost,
           store.hasStoredPassword(for: editingHost) {
            return L10n.SSHConnections.passwordStored
        }

        return L10n.SSHConnections.passwordNotStored
    }

    private var editingHost: AITerminalHost? {
        guard let editingHostID else { return nil }
        return allConnectionHosts.first(where: { $0.id == editingHostID })
    }

    private var learningSupportedPlaceholdersText: String {
        AITerminalLearningSettings.supportedPlaceholders.joined(separator: "  ")
    }

    private var learningLogEntries: [AITerminalLearningLogEntry] {
        store.learningLogs
    }

    private func filterHosts(_ hosts: [AITerminalHost]) -> [AITerminalHost] {
        let query = hostSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return hosts }

        return hosts.filter { host in
            host.name.localizedCaseInsensitiveContains(query)
                || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
                || host.startupCommands.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private func filterSavedWorkspaceTemplates(
        _ templates: [AITerminalSavedWorkspaceTemplate]
    ) -> [AITerminalSavedWorkspaceTemplate] {
        let query = hostSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }

        return templates.filter { template in
            template.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func savedWorkspaceSummary(for workspace: AITerminalSavedWorkspaceTemplate) -> String {
        let paneLabel = workspace.paneCount == 1 ? "1 pane" : "\(workspace.paneCount) panes"
        let tabLabel = workspace.tabCount == 1 ? "1 tab" : "\(workspace.tabCount) tabs"
        return "\(paneLabel) · \(tabLabel)"
    }

    private func hostSourceLabel(for host: AITerminalHost) -> String {
        if store.savedHosts.contains(where: { $0.id == host.id }) {
            return L10n.AITerminalManager.savedHostSource
        }

        if store.isImportedHost(host) {
            return store.isImportedHostOverridden(host)
                ? L10n.AITerminalManager.importedHostOverriddenSource
                : L10n.AITerminalManager.importedHostSource
        }

        return ""
    }

    private func recentSummary(for record: AITerminalRecentHostRecord) -> String {
        let status = recentStatusTitle(for: record)
        let timestamp = record.connectedAt.formatted(date: .abbreviated, time: .shortened)

        if let errorSummary = record.errorSummary, !errorSummary.isEmpty {
            return "\(status) • \(timestamp) • \(errorSummary)"
        }

        return "\(status) • \(timestamp)"
    }

    private func recentTimestamp(for record: AITerminalRecentHostRecord) -> String {
        record.connectedAt.formatted(date: .omitted, time: .shortened)
    }

    private func recentStatusTitle(for record: AITerminalRecentHostRecord) -> String {
        switch record.status {
        case .connected:
            L10n.AITerminalManager.hostStatusConnected
        case .failed:
            L10n.AITerminalManager.hostStatusFailed
        }
    }

    private func primarySubtitle(for host: AITerminalHost) -> String {
        host.connectionTarget ?? host.displaySubtitle
    }

    private func contextualRemoteSessions(for host: AITerminalHost) -> [AITerminalRemoteSessionSummary] {
        store.remoteSessions.filter { $0.hostID == host.id }
    }

    private func hasActiveSession(for host: AITerminalHost) -> Bool {
        store.remoteSessions.contains { $0.hostID == host.id }
    }

    private var selectedHost: AITerminalHost? {
        guard let selectedHostID else { return nil }
        return allConnectionHosts.first(where: { $0.id == selectedHostID })
    }
}

extension SSHConnectionsView {
    static func sidebarFavoriteHosts(
        favoriteHosts: [AITerminalHost]
    ) -> [AITerminalHost] {
        deduplicatedRecentHosts(favoriteHosts, limit: favoriteHosts.count)
    }

    static func sidebarRecentHosts(
        recentHosts: [AITerminalHost],
        favoriteHosts: [AITerminalHost]
    ) -> [AITerminalHost] {
        let favoriteIDs = Set(favoriteHosts.map(\.id))
        return deduplicatedRecentHosts(recentHosts.filter { !favoriteIDs.contains($0.id) })
    }

    static func deduplicatedRecentHosts(
        _ recentHosts: [AITerminalHost],
        limit: Int = 3
    ) -> [AITerminalHost] {
        var seen: Set<String> = []
        var result: [AITerminalHost] = []

        for host in recentHosts where seen.insert(host.id).inserted {
            result.append(host)
            if result.count == limit {
                break
            }
        }

        return result
    }

    static func sidebarSavedHosts(
        savedHosts: [AITerminalHost],
        favoriteHosts: [AITerminalHost],
        recentHosts: [AITerminalHost]
    ) -> [AITerminalHost] {
        let hiddenIDs = Set(favoriteHosts.map(\.id)).union(recentHosts.map(\.id))
        return savedHosts.filter { !hiddenIDs.contains($0.id) }
    }

    static func sidebarImportedHosts(
        importedHosts: [AITerminalHost],
        favoriteHosts: [AITerminalHost],
        savedHosts: [AITerminalHost],
        recentHosts: [AITerminalHost]
    ) -> [AITerminalHost] {
        let hiddenIDs = Set(savedHosts.map(\.id))
            .union(recentHosts.map(\.id))
            .union(favoriteHosts.map(\.id))
        return importedHosts.filter { !hiddenIDs.contains($0.id) }
    }
}

#Preview {
    SSHConnectionsView(presentation: SSHConnectionsPresentationState())
        .environmentObject(AppDelegate())
        .environmentObject(
            AITerminalManagerStore(
                appDelegateProvider: { nil },
                configurationURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json")
            )
        )
}
