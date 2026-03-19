import Foundation

struct NewTabPickerEntry: Identifiable, Hashable {
    enum Section: Hashable {
        case browser
        case local
        case favorites
        case recent
        case saved
        case imported
    }

    enum Destination: Hashable {
        case browser
        case host(AITerminalHost)
    }

    let destination: Destination
    let section: Section
    let shortcutIndex: Int?

    var id: String {
        switch destination {
        case .browser:
            return "browser"
        case .host(let host):
            return host.id
        }
    }

    var title: String {
        switch destination {
        case .browser:
            return AppLocalization.localizedText("Browser")
        case .host(let host):
            return host.name
        }
    }

    var subtitle: String {
        switch destination {
        case .browser:
            return AppLocalization.localizedText("Open a web page inside a GhoDex tab")
        case .host(let host):
            return host.connectionTarget ?? host.displaySubtitle
        }
    }

    var iconName: String {
        switch destination {
        case .browser:
            return "globe"
        case .host(let host):
            switch host.transport {
            case .local, .localmcd:
                return "laptopcomputer"
            case .ssh:
                return "arrow.up.right.square"
            }
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
        hasStoredPassword: (AITerminalHost) -> Bool
    ) -> [NewTabPickerEntry] {
        var entries: [NewTabPickerEntry] = [
            .init(destination: .host(.local), section: .local, shortcutIndex: 1),
        ]
        var seen: Set<String> = [AITerminalHost.local.id]
        var shortcutIndex = 2

        func append(_ hosts: [AITerminalHost], section: NewTabPickerEntry.Section) {
            for host in hosts {
                guard seen.insert(host.id).inserted else { continue }
                guard isLaunchable(host: host, hasStoredPassword: hasStoredPassword(host)) else { continue }
                entries.append(.init(
                    destination: .host(host),
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

    static func withBrowserEntry(
        _ entries: [NewTabPickerEntry],
        includeBrowserEntry: Bool
    ) -> [NewTabPickerEntry] {
        guard includeBrowserEntry else { return entries }

        var result = entries
        let browserEntry = NewTabPickerEntry(destination: .browser, section: .browser, shortcutIndex: 1)
        result.insert(browserEntry, at: 0)

        return result.enumerated().map { index, entry in
            .init(
                destination: entry.destination,
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

        return entries.filter { matches(entry: $0, query: normalizedQuery) }
    }

    private static func matches(entry: NewTabPickerEntry, query: String) -> Bool {
        switch entry.destination {
        case .browser:
            return entry.title.localizedCaseInsensitiveContains(query)
                || entry.subtitle.localizedCaseInsensitiveContains(query)

        case .host(let host):
            return host.name.localizedCaseInsensitiveContains(query)
                || host.displaySubtitle.localizedCaseInsensitiveContains(query)
                || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
                || host.startupCommands.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
}
