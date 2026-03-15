import Foundation

struct NewTabPickerEntry: Identifiable, Hashable {
    enum Section: Hashable {
        case local
        case favorites
        case recent
        case saved
        case imported
    }

    let host: AITerminalHost
    let section: Section
    let shortcutIndex: Int?

    var id: String { host.id }
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
        hasStoredPassword: (AITerminalHost) -> Bool
    ) -> [NewTabPickerEntry] {
        var entries: [NewTabPickerEntry] = [
            .init(host: .local, section: .local, shortcutIndex: 1),
        ]
        var seen: Set<String> = [AITerminalHost.local.id]
        var shortcutIndex = 2

        func append(_ hosts: [AITerminalHost], section: NewTabPickerEntry.Section) {
            for host in hosts {
                guard seen.insert(host.id).inserted else { continue }
                guard isLaunchable(host: host, hasStoredPassword: hasStoredPassword(host)) else { continue }
                entries.append(.init(
                    host: host,
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

        return entries
    }

    static func filteredEntries(
        _ entries: [NewTabPickerEntry],
        query: String
    ) -> [NewTabPickerEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter { matches(host: $0.host, query: normalizedQuery) }
    }

    private static func matches(host: AITerminalHost, query: String) -> Bool {
        host.name.localizedCaseInsensitiveContains(query)
            || host.displaySubtitle.localizedCaseInsensitiveContains(query)
            || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
            || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
            || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
            || host.startupCommands.contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }
}
