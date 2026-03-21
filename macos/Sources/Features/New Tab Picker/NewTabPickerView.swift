import SwiftUI

struct NewTabPickerView: View {
    @EnvironmentObject private var store: AITerminalManagerStore
    @EnvironmentObject private var theme: GhosttyChromeTheme

    let mode: NewTabPickerMode
    let title: String
    let subtitle: String
    let onClose: () -> Void
    let onOpenHost: ((AITerminalHost) -> Void)?
    let onOpenWorkspace: ((AITerminalSavedWorkspaceTemplate) -> Void)?

    @State private var searchText = ""
    @State private var selectedID: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(theme.isLight ? 0.24 : 0.34))

            TextField(L10n.SSHConnections.newTabPickerSearch, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)
                .backport.onKeyPress(.tab) { modifiers in
                    guard !entries.isEmpty else { return .handled }
                    moveSelection(modifiers.contains(.shift) ? -1 : 1)
                    return .handled
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let localEntry = entries.first(where: { $0.section == .local }) {
                            section(title: nil, entries: [localEntry])
                        }

                        if !favoriteEntries.isEmpty {
                            section(title: L10n.AITerminalManager.favoriteHosts, entries: favoriteEntries)
                        }

                        if !recentEntries.isEmpty {
                            section(title: L10n.AITerminalManager.recentHosts, entries: recentEntries)
                        }

                        if !savedEntries.isEmpty {
                            section(title: L10n.AITerminalManager.savedHosts, entries: savedEntries)
                        }

                        if !savedWorkspaceEntries.isEmpty {
                            section(title: L10n.AITerminalManager.savedWorkspacesSection, entries: savedWorkspaceEntries)
                        }

                        if !importedEntries.isEmpty {
                            section(title: L10n.AITerminalManager.importedHosts, entries: importedEntries)
                        }
                    }
                    .padding(16)
                }
            }

            footer
        }
        .frame(width: 860, height: 640)
        .background(GhosttyTintedBackground().ignoresSafeArea())
        .environment(\.colorScheme, theme.colorScheme)
        .overlay(shortcutLayer)
        .onAppear {
            selectedID = entries.first?.id
            DispatchQueue.main.async {
                searchFieldFocused = true
            }
        }
        .onChange(of: entries.map(\.id)) { ids in
            guard let first = ids.first else {
                selectedID = nil
                return
            }

            if let selectedID, ids.contains(selectedID) {
                return
            }

            self.selectedID = first
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.SSHConnections.newTabPickerEmpty)
                .foregroundStyle(.secondary)

            Button(L10n.SSHConnections.windowTitle) {
                onClose()
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.showSSHConnections(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private func section(
        title: String?,
        entries: [NewTabPickerEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    private func row(for entry: NewTabPickerEntry) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: 12) {
                shortcutBadge(entry.shortcutIndex)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(primaryTitle(for: entry))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let label = sourceLabel(for: entry), !label.isEmpty {
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Color.white.opacity(theme.isLight ? 0.78 : 0.08),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(primarySubtitle(for: entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                Image(systemName: iconName(for: entry))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(for: entry), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(rowBorder(for: entry), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func shortcutBadge(_ shortcutIndex: Int?) -> some View {
        let title = shortcutIndex.map(String.init) ?? "·"

        return Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(
                Color.white.opacity(theme.isLight ? 0.82 : 0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }

    private var footer: some View {
        HStack {
            Text("↩︎ \(L10n.AITerminalManager.connect) · Esc \(L10n.Common.cancel) · \(L10n.SSHConnections.newTabPickerQuickConnect)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.Common.cancel) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(theme.isLight ? 0.32 : 0.03))
    }

    private var shortcutLayer: some View {
        ZStack {
            Group {
                Button { moveSelection(-1) } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.upArrow, modifiers: [])

                Button { moveSelection(1) } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button { submitSelection() } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            ForEach(Array(entries.enumerated()), id: \.1.id) { _, entry in
                if let shortcutIndex = entry.shortcutIndex,
                   let character = String(shortcutIndex).first,
                   let key = KeyEquivalent(character) {
                    Button { open(entry) } label: { Color.clear }
                        .buttonStyle(.plain)
                        .keyboardShortcut(key, modifiers: [])
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)

                    Button { open(entry) } label: { Color.clear }
                        .buttonStyle(.plain)
                        .keyboardShortcut(key, modifiers: [.command])
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var entries: [NewTabPickerEntry] {
        NewTabPickerModel.filteredEntries(store.newTabPickerEntries(mode: mode), query: searchText)
    }

    private var favoriteEntries: [NewTabPickerEntry] {
        entries.filter { $0.section == .favorites }
    }

    private var recentEntries: [NewTabPickerEntry] {
        entries.filter { $0.section == .recent }
    }

    private var savedEntries: [NewTabPickerEntry] {
        entries.filter { $0.section == .saved }
    }

    private var importedEntries: [NewTabPickerEntry] {
        entries.filter { $0.section == .imported }
    }

    private var savedWorkspaceEntries: [NewTabPickerEntry] {
        entries.filter { $0.section == .savedWorkspaces }
    }

    private func moveSelection(_ offset: Int) {
        guard !entries.isEmpty else { return }

        let currentIndex = entries.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = max(0, min(entries.count - 1, currentIndex + offset))
        selectedID = entries[nextIndex].id
    }

    private func submitSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) ?? entries.first else { return }
        open(entry)
    }

    private func open(_ entry: NewTabPickerEntry) {
        switch entry.kind {
        case .host(let host):
            if let onOpenHost {
                onOpenHost(host)
            } else {
                store.openInNewTab(host: host)
            }
        case .savedWorkspace(let workspace):
            if let onOpenWorkspace {
                onOpenWorkspace(workspace)
            } else {
                store.open(savedWorkspaceTemplate: workspace)
            }
        }
        onClose()
    }

    private func primaryTitle(for entry: NewTabPickerEntry) -> String {
        switch entry.kind {
        case .host(let host):
            return host.name
        case .savedWorkspace(let workspace):
            return workspace.name
        }
    }

    private func primarySubtitle(for entry: NewTabPickerEntry) -> String {
        switch entry.kind {
        case .host(let host):
            return host.connectionTarget ?? host.displaySubtitle
        case .savedWorkspace(let workspace):
            let paneLabel = workspace.paneCount == 1 ? "1 pane" : "\(workspace.paneCount) panes"
            let tabLabel = workspace.tabCount == 1 ? "1 tab" : "\(workspace.tabCount) tabs"
            return "\(paneLabel) · \(tabLabel)"
        }
    }

    private func sourceLabel(for entry: NewTabPickerEntry) -> String? {
        switch entry.section {
        case .local:
            return nil
        case .favorites:
            return L10n.AITerminalManager.favoriteHosts
        case .recent:
            return L10n.AITerminalManager.recentHosts
        case .saved:
            return L10n.AITerminalManager.savedHostSource
        case .imported:
            return L10n.AITerminalManager.importedHostSource
        case .savedWorkspaces:
            return L10n.AITerminalManager.savedWorkspaceItem
        }
    }

    private func iconName(for entry: NewTabPickerEntry) -> String {
        switch entry.kind {
        case .host(let host):
            switch host.transport {
            case .local, .localmcd:
                return "laptopcomputer"
            case .ssh:
                return "arrow.up.right.square"
            }
        case .savedWorkspace:
            return "square.grid.2x2"
        }
    }

    private func rowBackground(for entry: NewTabPickerEntry) -> Color {
        if selectedID == entry.id {
            return Color.accentColor.opacity(theme.isLight ? 0.12 : 0.18)
        }

        return Color.white.opacity(theme.isLight ? 0.58 : 0.05)
    }

    private func rowBorder(for entry: NewTabPickerEntry) -> Color {
        if selectedID == entry.id {
            return Color.accentColor.opacity(theme.isLight ? 0.24 : 0.32)
        }

        return Color(nsColor: .separatorColor).opacity(theme.isLight ? 0.18 : 0.22)
    }
}

private extension KeyEquivalent {
    init?(_ character: Character) {
        switch character {
        case "0"..."9":
            self = .init(character)
        default:
            return nil
        }
    }
}
