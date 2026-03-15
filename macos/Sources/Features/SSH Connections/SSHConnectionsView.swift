import AppKit
import Foundation
import SwiftUI

struct SSHConnectionsView: View {
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

    private struct VisualEffectBackground: NSViewRepresentable {
        let material: NSVisualEffectView.Material

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.state = .active
            view.blendingMode = .behindWindow
            view.material = material
            return view
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
        }
    }

    @Environment(\.colorScheme) private var colorScheme
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
    @State private var hostSearchText = ""

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let lastError = store.lastError, !lastError.isEmpty {
                    errorBanner(lastError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                HStack(alignment: .top, spacing: 20) {
                    sidebarPanel
                        .frame(width: 340)

                    detailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 1240, minHeight: 780)
        .sheet(isPresented: $isPresentingEditor) {
            hostEditorSheet
        }
        .onAppear(perform: syncSelection)
        .onChange(of: allConnectionHosts.map(\.id)) { _ in
            syncSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.SSHConnections.title)
                    .font(.title2.weight(.semibold))

                Text(L10n.SSHConnections.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(L10n.AITerminalManager.launch)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.AITerminalManager.launch, selection: $store.launchTarget) {
                    ForEach(AITerminalLaunchTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
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
                    if displayFavoriteHosts.isEmpty && displayRecentHosts.isEmpty && displaySavedHosts.isEmpty && displayImportedHosts.isEmpty {
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func recentHostRow(_ host: AITerminalHost) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedHostID = host.id
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(host.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if store.isFavorite(host) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
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
            }
            .buttonStyle(.plain)

            Button {
                store.open(host: host)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .background(rowBackground(for: host), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(rowBorder(for: host), lineWidth: 1)
        )
    }

    private func sidebarHostRow(_ host: AITerminalHost) -> some View {
        Button {
            selectedHostID = host.id
        } label: {
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
                                .foregroundStyle(Color.accentColor)
                        }

                        if hasActiveSession(for: host) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .foregroundStyle(Color.accentColor)
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
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            store.open(host: host)
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
                Text(L10n.SSHConnections.title)
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
            .foregroundStyle(recentRecord.status == .failed ? .red : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (recentRecord.status == .failed ? Color.red : Color.accentColor).opacity(0.12),
                in: Capsule()
            )
    }

    private func rowBackground(for host: AITerminalHost) -> Color {
        if selectedHostID == host.id {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }

        return Color.white.opacity(colorScheme == .dark ? 0.035 : 0.55)
    }

    private func rowBorder(for host: AITerminalHost) -> Color {
        if selectedHostID == host.id {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.2)
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

        selectedHostID = allConnectionHosts.first?.id
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
    SSHConnectionsView()
        .environmentObject(
            AITerminalManagerStore(
                appDelegateProvider: { nil },
                configurationURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json")
            )
        )
}
