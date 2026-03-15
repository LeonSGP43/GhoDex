import Foundation
import GhosttyKit

enum AITerminalManagedState: String, Codable, CaseIterable, Sendable {
    case manual
    case observed
    case managedActive = "managed_active"
    case managedWaitingApproval = "managed_waiting_approval"
    case managedPaused = "managed_paused"
    case managedCompleted = "managed_completed"
    case managedFailed = "managed_failed"

    var displayName: String {
        switch self {
        case .manual: L10n.AITerminalManager.manual
        case .observed: L10n.AITerminalManager.observed
        case .managedActive: L10n.AITerminalManager.managed
        case .managedWaitingApproval: L10n.AITerminalManager.awaitingApproval
        case .managedPaused: L10n.AITerminalManager.paused
        case .managedCompleted: L10n.AITerminalManager.completed
        case .managedFailed: L10n.AITerminalManager.failed
        }
    }
}

enum AITerminalLaunchTarget: String, CaseIterable, Identifiable {
    case tab
    case window

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: L10n.AITerminalManager.newTab
        case .window: L10n.AITerminalManager.newWindow
        }
    }
}

enum AITerminalHostSource: String, Codable, Sendable {
    case builtIn = "built_in"
    case configurationFile = "configuration_file"
    case sshConfig = "ssh_config"

    var isUserManaged: Bool {
        switch self {
        case .builtIn, .sshConfig:
            false
        case .configurationFile:
            true
        }
    }
}

enum AITerminalTransport: String, Codable, Sendable {
    case local
    case localmcd
    case ssh
}

enum AITerminalHostAuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case password

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.SSHConnections.authModeSystem
        case .password: L10n.SSHConnections.authModePassword
        }
    }
}

struct AITerminalHost: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var transport: AITerminalTransport
    var startupCommands: [String]
    var sshAlias: String?
    var hostname: String?
    var user: String?
    var port: Int?
    var defaultDirectory: String?
    var source: AITerminalHostSource
    var authMode: AITerminalHostAuthMode

    init(
        id: String,
        name: String,
        transport: AITerminalTransport,
        startupCommands: [String] = [],
        sshAlias: String?,
        hostname: String?,
        user: String?,
        port: Int?,
        defaultDirectory: String?,
        source: AITerminalHostSource,
        authMode: AITerminalHostAuthMode = .system
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.startupCommands = startupCommands
        self.sshAlias = sshAlias
        self.hostname = hostname
        self.user = user
        self.port = port
        self.defaultDirectory = defaultDirectory
        self.source = source
        self.authMode = authMode
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case transport
        case startupCommands
        case sshAlias
        case hostname
        case user
        case port
        case defaultDirectory
        case source
        case authMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decode(AITerminalTransport.self, forKey: .transport)
        startupCommands = try container.decodeIfPresent([String].self, forKey: .startupCommands) ?? []
        sshAlias = try container.decodeIfPresent(String.self, forKey: .sshAlias)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        defaultDirectory = try container.decodeIfPresent(String.self, forKey: .defaultDirectory)
        source = try container.decode(AITerminalHostSource.self, forKey: .source)
        authMode = try container.decodeIfPresent(AITerminalHostAuthMode.self, forKey: .authMode) ?? .system
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(transport, forKey: .transport)
        try container.encode(startupCommands, forKey: .startupCommands)
        try container.encodeIfPresent(sshAlias, forKey: .sshAlias)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(defaultDirectory, forKey: .defaultDirectory)
        try container.encode(source, forKey: .source)
        try container.encode(authMode, forKey: .authMode)
    }

    static let local = AITerminalHost(
        id: "local",
        name: L10n.AITerminalManager.thisMac,
        transport: .local,
        startupCommands: [],
        sshAlias: nil,
        hostname: nil,
        user: nil,
        port: nil,
        defaultDirectory: nil,
        source: .builtIn,
        authMode: .system
    )

    var isLocal: Bool { transport == .local }

    var displaySubtitle: String {
        switch transport {
        case .local:
            return defaultDirectory ?? L10n.AITerminalManager.localShell
        case .localmcd:
            if startupCommands.isEmpty {
                return defaultDirectory ?? L10n.AITerminalManager.localShell
            }
            return startupCommands.joined(separator: "  •  ")
        case .ssh:
            var parts: [String] = []
            if let sshAlias, !sshAlias.isEmpty {
                parts.append(sshAlias)
            }
            if let hostname, !hostname.isEmpty, hostname != sshAlias {
                parts.append(hostname)
            }
            if let user, !user.isEmpty {
                parts.append(user)
            }
            if let port = port {
                parts.append(":\(port)")
            }
            if let defaultDirectory, !defaultDirectory.isEmpty {
                parts.append(defaultDirectory)
            }
            return parts.joined(separator: " • ")
        }
    }

    var connectionTarget: String? {
        if let sshAlias, !sshAlias.isEmpty {
            return sshAlias
        }
        guard let hostname, !hostname.isEmpty else { return nil }
        if let user, !user.isEmpty {
            return "\(user)@\(hostname)"
        }
        return hostname
    }

    static func stableID(
        existingID: String? = nil,
        sshAlias: String,
        hostname: String,
        user: String
    ) -> String {
        if let existingID, !existingID.isEmpty {
            return existingID
        }

        let trimmedAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlias.isEmpty {
            return "ssh:\(trimmedAlias)"
        }

        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableKey = trimmedUser.isEmpty ? trimmedHostname : "\(trimmedUser)@\(trimmedHostname)"
        return "configured:\(stableKey)"
    }
}

struct AITerminalRecentHostRecord: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case connected
        case failed
    }

    let id: String
    var connectedAt: Date
    var status: Status
    var errorSummary: String?

    init(
        id: String,
        connectedAt: Date = .now,
        status: Status,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.connectedAt = connectedAt
        self.status = status
        self.errorSummary = errorSummary
    }
}

struct AITerminalWorkspaceTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var hostID: String
    var directory: String
}

struct AITerminalManagerConfiguration: Codable, Sendable {
    var schemaVersion: Int
    var savedHosts: [AITerminalHost]
    var importedHostOverrides: [AITerminalHost]
    var favoriteHostIDs: [String]
    var recentHosts: [AITerminalRecentHostRecord]
    var workspaces: [AITerminalWorkspaceTemplate]

    init(
        schemaVersion: Int = 2,
        savedHosts: [AITerminalHost] = [],
        importedHostOverrides: [AITerminalHost] = [],
        favoriteHostIDs: [String] = [],
        recentHosts: [AITerminalRecentHostRecord] = [],
        workspaces: [AITerminalWorkspaceTemplate] = []
    ) {
        self.schemaVersion = schemaVersion
        self.savedHosts = savedHosts
        self.importedHostOverrides = importedHostOverrides
        self.favoriteHostIDs = favoriteHostIDs
        self.recentHosts = recentHosts
        self.workspaces = workspaces
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedHosts
        case importedHostOverrides
        case favoriteHostIDs
        case recentHosts
        case workspaces
        case hosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        savedHosts = try container.decodeIfPresent([AITerminalHost].self, forKey: .savedHosts)
            ?? container.decodeIfPresent([AITerminalHost].self, forKey: .hosts)
            ?? []
        importedHostOverrides = try container.decodeIfPresent([AITerminalHost].self, forKey: .importedHostOverrides) ?? []
        favoriteHostIDs = try container.decodeIfPresent([String].self, forKey: .favoriteHostIDs) ?? []
        recentHosts = try container.decodeIfPresent([AITerminalRecentHostRecord].self, forKey: .recentHosts) ?? []
        workspaces = try container.decodeIfPresent([AITerminalWorkspaceTemplate].self, forKey: .workspaces) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(savedHosts, forKey: .savedHosts)
        try container.encode(importedHostOverrides, forKey: .importedHostOverrides)
        try container.encode(favoriteHostIDs, forKey: .favoriteHostIDs)
        try container.encode(recentHosts, forKey: .recentHosts)
        try container.encode(workspaces, forKey: .workspaces)
    }
}

struct AITerminalLaunchRegistration: Hashable, Sendable {
    var hostID: String?
    var workspaceID: String?
    var managedState: AITerminalManagedState
    var sourceLabel: String
}

enum AITerminalSSHSessionAuthState: String, Hashable, Sendable {
    case connecting
    case awaitingPassword = "awaiting_password"
    case authenticating
    case connected
    case failed

    var displayName: String {
        switch self {
        case .connecting: L10n.SSHConnections.authStateConnecting
        case .awaitingPassword: L10n.SSHConnections.authStateAwaitingPassword
        case .authenticating: L10n.SSHConnections.authStateAuthenticating
        case .connected: L10n.SSHConnections.authStateConnected
        case .failed: L10n.SSHConnections.authStateFailed
        }
    }
}

struct AITerminalRemoteSessionSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var hostID: String
    var hostName: String
    var hostTarget: String
    var workingDirectory: String?
    var authState: AITerminalSSHSessionAuthState
    var isFocused: Bool
}

struct AITerminalSessionSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var workingDirectory: String?
    var isFocused: Bool
    var hostLabel: String
    var managedState: AITerminalManagedState
    var taskID: UUID?
    var taskTitle: String?
    var taskState: AITerminalTaskState?
}

enum AITerminalTaskState: String, Codable, CaseIterable, Sendable {
    case queued
    case active
    case waitingApproval = "waiting_approval"
    case paused
    case completed
    case failed

    var displayName: String {
        switch self {
        case .queued: L10n.AITerminalManager.queued
        case .active: L10n.AITerminalManager.active
        case .waitingApproval: L10n.AITerminalManager.awaitingApproval
        case .paused: L10n.AITerminalManager.paused
        case .completed: L10n.AITerminalManager.completed
        case .failed: L10n.AITerminalManager.failed
        }
    }
}

struct AITerminalTaskRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var sessionID: UUID
    var state: AITerminalTaskState
    var createdAt: Date
    var updatedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        sessionID: UUID,
        state: AITerminalTaskState = .queued,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sessionID = sessionID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }
}

struct AITerminalLaunchPlan {
    var surfaceConfiguration: Ghostty.SurfaceConfiguration
    var registration: AITerminalLaunchRegistration

    static func localShell() -> AITerminalLaunchPlan {
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local"
        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: AITerminalHost.local.id,
                workspaceID: nil,
                managedState: .manual,
                sourceLabel: AITerminalHost.local.name
            )
        )
    }

    static func workspace(
        _ workspace: AITerminalWorkspaceTemplate,
        host: AITerminalHost
    ) -> AITerminalLaunchPlan? {
        switch host.transport {
        case .local:
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = workspace.directory
            config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
            config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local_workspace"
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspace.id
            return .init(
                surfaceConfiguration: config,
                registration: .init(
                    hostID: host.id,
                    workspaceID: workspace.id,
                    managedState: .manual,
                    sourceLabel: workspace.name
                )
            )

        case .localmcd:
            return localCommand(
                host: host,
                directoryOverride: workspace.directory,
                workspaceID: workspace.id,
                sourceLabel: workspace.name
            )

        case .ssh:
            return remote(host: host, directoryOverride: workspace.directory, workspaceID: workspace.id, sourceLabel: workspace.name)
        }
    }

    static func localCommand(
        host: AITerminalHost,
        directoryOverride: String? = nil,
        workspaceID: String? = nil,
        sourceLabel: String? = nil
    ) -> AITerminalLaunchPlan? {
        guard host.transport == .localmcd else { return nil }
        let startupCommands = host.startupCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !startupCommands.isEmpty else { return nil }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = directoryOverride ?? host.defaultDirectory
        config.initialInput = startupCommands.joined(separator: "\n") + "\n"
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local_mcd"
        config.environmentVariables["GHOSTTY_AI_HOST_ID"] = host.id
        if let workspaceID = workspaceID {
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspaceID
        }

        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: host.id,
                workspaceID: workspaceID,
                managedState: .manual,
                sourceLabel: sourceLabel ?? host.name
            )
        )
    }

    static func remote(
        host: AITerminalHost,
        directoryOverride: String? = nil,
        workspaceID: String? = nil,
        sourceLabel: String? = nil
    ) -> AITerminalLaunchPlan? {
        guard let command = remoteCommand(host: host, directoryOverride: directoryOverride) else {
            return nil
        }

        var config = Ghostty.SurfaceConfiguration()
        config.command = command
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "remote_ssh"
        config.environmentVariables["GHOSTTY_AI_HOST_ID"] = host.id
        if let workspaceID = workspaceID {
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspaceID
        }

        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: host.id,
                workspaceID: workspaceID,
                managedState: .manual,
                sourceLabel: sourceLabel ?? host.name
            )
        )
    }

    static func remoteCommand(
        host: AITerminalHost,
        directoryOverride: String? = nil
    ) -> String? {
        guard let target = host.connectionTarget else { return nil }

        var command = "ssh"
        if host.sshAlias == nil, let port = host.port {
            command += " -p \(port)"
        }
        command += " \(Ghostty.Shell.quote(target))"

        let directory = directoryOverride ?? host.defaultDirectory
        let remoteShell: String
        if let directory, !directory.isEmpty {
            remoteShell = "export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && cd \(Ghostty.Shell.quote(directory)) && exec ${SHELL:-/bin/sh} -l"
        } else {
            remoteShell = "export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && exec ${SHELL:-/bin/sh} -l"
        }
        command += " -t \(Ghostty.Shell.quote(remoteShell))"

        return command
    }
}

enum AITerminalSSHConfigParser {
    private struct Accumulator {
        var aliases: [String] = []
        var hostname: String?
        var user: String?
        var port: Int?
    }

    static func parse(_ text: String) -> [AITerminalHost] {
        var result: [AITerminalHost] = []
        var current = Accumulator()

        func flush() {
            guard !current.aliases.isEmpty else { return }
            for alias in current.aliases {
                result.append(
                    AITerminalHost(
                        id: "ssh:\(alias)",
                        name: alias,
                        transport: .ssh,
                        sshAlias: alias,
                        hostname: current.hostname,
                        user: current.user,
                        port: current.port,
                        defaultDirectory: nil,
                        source: .sshConfig
                    )
                )
            }
            current = Accumulator()
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let line = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = parts.first?.lowercased(), parts.count >= 2 else { continue }

            switch key {
            case "host":
                flush()
                current.aliases = parts.dropFirst().filter {
                    !$0.contains("*") && !$0.contains("?") && !$0.contains("!")
                }

            case "hostname":
                current.hostname = parts.dropFirst().joined(separator: " ")

            case "user":
                current.user = parts.dropFirst().joined(separator: " ")

            case "port":
                current.port = Int(parts.dropFirst().joined(separator: " "))

            default:
                continue
            }
        }

        flush()

        var seen: Set<String> = []
        return result.filter { seen.insert($0.id).inserted }
    }
}

extension AITerminalManagerConfiguration {
    static let empty = AITerminalManagerConfiguration()
}
