import Foundation

enum NewTabPickerMode: Hashable {
    case topLevel
    case paneChild
}

struct NewTabPickerEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case browser
        case host(AITerminalHost)
        case savedWorkspace(AITerminalSavedWorkspaceTemplate)
    }

    enum Section: Hashable {
        case browser
        case local
        case favorites
        case recent
        case saved
        case imported
        case savedWorkspaces
    }

    let kind: Kind
    let section: Section
    let shortcutIndex: Int?

    var id: String {
        switch kind {
        case .browser:
            return "browser"
        case .host(let host):
            return host.id
        case .savedWorkspace(let workspace):
            return workspace.id
        }
    }
}

enum NewTabPickerModel {
    static func isLaunchable(
        host: AITerminalHost,
        hasStoredPassword: Bool
    ) -> Bool {
        switch host.transport {
        case .local:
            return true
        case .localmcd:
            return AITerminalLaunchPlan.localCommand(host: host) != nil
        case .ssh:
            guard AITerminalLaunchPlan.remote(host: host, directoryOverride: nil) != nil else {
                return false
            }

            if host.authMode == .password {
                return hasStoredPassword
            }

            return true
        }
    }

    static func entries(
        favoriteHosts: [AITerminalHost],
        recentHosts: [AITerminalHost],
        savedHosts: [AITerminalHost],
        importedHosts: [AITerminalHost],
        savedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate] = [],
        mode: NewTabPickerMode = .topLevel,
        hasStoredPassword: (AITerminalHost) -> Bool
    ) -> [NewTabPickerEntry] {
        var entries: [NewTabPickerEntry] = [
            .init(kind: .host(.local), section: .local, shortcutIndex: 1),
        ]
        var seen: Set<String> = [AITerminalHost.local.id]
        var shortcutIndex = 2

        func append(_ hosts: [AITerminalHost], section: NewTabPickerEntry.Section) {
            for host in hosts {
                guard seen.insert(host.id).inserted else { continue }
                guard isLaunchable(host: host, hasStoredPassword: hasStoredPassword(host)) else { continue }
                entries.append(.init(
                    kind: .host(host),
                    section: section,
                    shortcutIndex: shortcutIndex <= 9 ? shortcutIndex : nil
                ))
                shortcutIndex += 1
            }
        }

        append(favoriteHosts, section: .favorites)
        append(recentHosts, section: .recent)
        append(savedHosts, section: .saved)
        append(importedHosts, section: .imported)

        if mode == .topLevel {
            for workspace in savedWorkspaceTemplates {
                entries.append(.init(
                    kind: .savedWorkspace(workspace),
                    section: .savedWorkspaces,
                    shortcutIndex: shortcutIndex <= 9 ? shortcutIndex : nil
                ))
                shortcutIndex += 1
            }
        }

        return entries
    }

    static func withBrowserEntry(
        _ entries: [NewTabPickerEntry],
        includeBrowserEntry: Bool
    ) -> [NewTabPickerEntry] {
        var result = entries
        if includeBrowserEntry {
            result.insert(.init(kind: .browser, section: .browser, shortcutIndex: 1), at: 0)
        }

        return result.enumerated().map { index, entry in
            .init(
                kind: entry.kind,
                section: entry.section,
                shortcutIndex: index < 9 ? index + 1 : nil
            )
        }
    }

    static func filteredEntries(
        _ entries: [NewTabPickerEntry],
        query: String
    ) -> [NewTabPickerEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter {
            switch $0.kind {
            case .browser:
                return matchesBrowser(query: normalizedQuery)
            case .host(let host):
                return matches(host: host, query: normalizedQuery)
            case .savedWorkspace(let workspace):
                return matches(workspace: workspace, query: normalizedQuery)
            }
        }
    }

    private static func matchesBrowser(query: String) -> Bool {
        AppLocalization.localizedText("Browser").localizedCaseInsensitiveContains(query)
            || AppLocalization
            .localizedText("Open a web page inside a GhoDex tab")
            .localizedCaseInsensitiveContains(query)
    }


    private static func matches(host: AITerminalHost, query: String) -> Bool {
        host.name.localizedCaseInsensitiveContains(query)
            || host.displaySubtitle.localizedCaseInsensitiveContains(query)
            || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
            || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
            || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
            || host.startupCommands.contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }

    private static func matches(workspace: AITerminalSavedWorkspaceTemplate, query: String) -> Bool {
        guard !workspace.name.localizedCaseInsensitiveContains(query) else { return true }
        return savedWorkspaceSearchTokens(for: workspace).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private static func savedWorkspaceSearchTokens(for workspace: AITerminalSavedWorkspaceTemplate) -> [String] {
        func tokens(from node: AITerminalSavedWorkspaceNode) -> [String] {
            switch node {
            case .pane(let pane):
                return pane.tabs.compactMap { $0.directory } + pane.tabs.map(\.hostID)
            case .split(let split):
                return tokens(from: split.left) + tokens(from: split.right)
            }
        }

        return tokens(from: workspace.root)
    }
}
