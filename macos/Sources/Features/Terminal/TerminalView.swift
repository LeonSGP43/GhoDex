import SwiftUI
import GhoDexKit
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: Ghostty.SurfaceView)

    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<TerminalPane> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }

    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }
}

/// Optional pane-tab model for split leaves that host their own tab stacks.
protocol TerminalPaneTabModel: AnyObject {
    func focusPane(_ pane: TerminalPane)
    func selectPaneTab(_ tabID: UUID, in pane: TerminalPane)
    func newPaneTab(in pane: TerminalPane)
    func closePaneTab(_ tabID: UUID, in pane: TerminalPane)
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Ghostty.App

    // The required view model
    @ObservedObject var viewModel: ViewModel

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)?

    /// The most recently focused surface, equal to `focusedSurface` when it is non-nil.
    @State private var lastFocusedSurface: Weak<Ghostty.SurfaceView>?

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface
    @FocusedValue(\.ghosttySurfacePwd) private var surfacePwd
    @FocusedValue(\.ghosttySurfaceCellSize) private var cellSize

        // The pwd of the focused surface as a URL
    private var pwdURL: URL? {
        guard let surfacePwd, surfacePwd != "" else { return nil }
        return URL(fileURLWithPath: surfacePwd)
    }

    var body: some View {
        let paneTabModel = viewModel as? any TerminalPaneTabModel
        let terminalController = viewModel as? BaseTerminalController
        let appDelegate = NSApp.delegate as? AppDelegate
        let todoSidebarSafeAreaEdge = (appDelegate?.existingAITerminalManagerStore?.todoSettings.sidebarEdge ?? .leading).safeAreaEdge
        switch ghostty.readiness {
        case .loading:
            Text(AppLocalization.localizedText("Loading"))
        case .error:
            ErrorView()
        case .ready:
            ZStack {
                VStack(spacing: 0) {
                    // If we're running in debug mode we show a warning so that users
                    // know that performance will be degraded.
                    if Ghostty.info.mode == GHOSTTY_BUILD_MODE_DEBUG || Ghostty.info.mode == GHOSTTY_BUILD_MODE_RELEASE_SAFE {
                        DebugBuildWarningView()
                    }

                    TerminalSplitTreeView(
                        tree: viewModel.surfaceTree,
                        action: { delegate?.performSplitAction($0) },
                        onFocusPane: { paneTabModel?.focusPane($0) },
                        onSelectPaneTab: { paneTabModel?.selectPaneTab($1, in: $0) },
                        onNewPaneTab: { paneTabModel?.newPaneTab(in: $0) },
                        onClosePaneTab: { paneTabModel?.closePaneTab($1, in: $0) })
                        .environmentObject(ghostty)
                        .ghosttyLastFocusedSurface(lastFocusedSurface)
                        .focused($focused)
                        .onAppear { self.focused = true }
                        .onChange(of: focusedSurface) { newValue in
                            // We want to keep track of our last focused surface so even if
                            // we lose focus we keep this set to the last non-nil value.
                            if newValue != nil {
                                lastFocusedSurface = .init(newValue)
                                self.delegate?.focusedSurfaceDidChange(to: newValue)
                            }
                        }
                        .onChange(of: pwdURL) { newValue in
                            self.delegate?.pwdDidChange(to: newValue)
                        }
                        .onChange(of: cellSize) { newValue in
                            guard let size = newValue else { return }
                            self.delegate?.cellSizeDidChange(to: size)
                        }
                        .frame(idealWidth: lastFocusedSurface?.value?.initialSize?.width,
                               idealHeight: lastFocusedSurface?.value?.initialSize?.height)
                }
                // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                .ignoresSafeArea(.container, edges: ghostty.config.macosTitlebarStyle == "hidden" ? .top : [])

                if let surfaceView = lastFocusedSurface?.value {
                    TerminalCommandPaletteView(
                        surfaceView: surfaceView,
                        isPresented: $viewModel.commandPaletteIsShowing,
                        ghosttyConfig: ghostty.config,
                        updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel) { action in
                        self.delegate?.performAction(action, on: surfaceView)
                    }
                }

                if let terminalController, let store = appDelegate?.aiTerminalManagerStore {
                    TodoWorkspaceOverlay(
                        store: store,
                        workspaceID: terminalController.workspaceID,
                        workspaceTitle: terminalController.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? terminalController.titleOverride!
                            : (terminalController.window?.title ?? "Tab"),
                        parentWindow: terminalController.window,
                        isSidebarPresented: terminalController.todoSidebarIsPresented
                    )
                }

                // Show update information above all else.
                if viewModel.updateOverlayIsVisible {
                    UpdateOverlay()
                }
            }
            .safeAreaInset(edge: todoSidebarSafeAreaEdge, spacing: 0) {
                if let terminalController,
                   let store = appDelegate?.aiTerminalManagerStore,
                   terminalController.todoSidebarIsPresented {
                    TodoWorkspaceSidebar(
                        store: store,
                        terminalController: terminalController,
                        parentWindow: terminalController.window,
                        sidebarEdge: store.todoSettings.sidebarEdge
                    )
                    .transition(
                        .move(edge: todoSidebarSafeAreaEdge == .leading ? .leading : .trailing)
                        .combined(with: .opacity)
                    )
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: terminalController?.todoSidebarIsPresented ?? false)
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }
}

private struct TodoWorkspaceOverlay: View {
    @ObservedObject var store: AITerminalManagerStore

    let workspaceID: UUID
    let workspaceTitle: String
    weak var parentWindow: NSWindow?
    let isSidebarPresented: Bool

    @State private var expanded = true

    private let rowLimit = 3

    private var summary: AITerminalTodoWorkspaceProgressSummary {
        store.todoWorkspaceSummary(for: workspaceID)
    }

    private var items: [AITerminalTodoItem] {
        store.todoItems(assignedTo: workspaceID, includeCompleted: true)
    }

    private var visibleItems: ArraySlice<AITerminalTodoItem> {
        items.prefix(expanded ? rowLimit : 0)
    }

    var body: some View {
        if store.todoSettings.enabled,
           store.todoSettings.workspaceOverlayVisible,
           !isSidebarPresented,
           summary.totalCount > 0 {
            overlayCard
                .padding(12)
                .frame(
                    maxWidth: .greatestFiniteMagnitude,
                    maxHeight: .greatestFiniteMagnitude,
                    alignment: store.todoSettings.workspaceOverlayCorner.alignment
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
        }
    }

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.SSHConnections.todoQuickLookTitle)
                        .font(.headline)

                    Text(workspaceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(L10n.SSHConnections.todoQuickLookSummary(
                        summary.completedCount,
                        summary.totalCount,
                        summary.remainingCount
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .help(L10n.SSHConnections.todoQuickLookTitle)

                Button(L10n.SSHConnections.todoQuickLookManage) {
                    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                    _ = appDelegate.toggleTodoSidebar(
                        focusedWorkspaceID: workspaceID,
                        from: parentWindow
                    )
                }
                .buttonStyle(.borderless)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(visibleItems), id: \.id) { item in
                        todoItemRow(item)
                    }

                    if items.count > rowLimit {
                        Text(L10n.SSHConnections.todoQuickLookMore(items.count - rowLimit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func todoItemRow(_ item: AITerminalTodoItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                _ = store.setTodoItemCompleted(
                    id: item.id,
                    isCompleted: !item.isCompleted,
                    for: .now
                )
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct TodoWorkspaceSidebar: View {
    @ObservedObject var store: AITerminalManagerStore
    @ObservedObject var terminalController: BaseTerminalController

    weak var parentWindow: NSWindow?
    let sidebarEdge: AITerminalTodoSidebarEdge

    @State private var selectedDate = Date.now
    @State private var showCompletedItems = true
    @State private var todoDocument = AITerminalTodoDayDocument()
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var composerIsExpanded = false
    @State private var composerShowsNotes = false
    @State private var editingItemID: UUID?
    @State private var editingTitle = ""
    @State private var editingNotes = ""
    @State private var statusMessage: String?
    @FocusState private var composerTitleFieldFocused: Bool

    private var workspaceTitle: String {
        let trimmed = terminalController.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return terminalController.window?.title ?? "Tab"
    }

    private var workspaceTargets: [AITerminalTodoWorkspaceTarget] {
        store.liveTodoWorkspaceTargets()
    }

    private var summary: AITerminalTodoWorkspaceProgressSummary {
        store.todoWorkspaceSummary(for: terminalController.workspaceID, on: selectedDate)
    }

    private var visibleTodoItems: [AITerminalTodoItem] {
        let ordered = todoDocument.orderedItems
        guard !showCompletedItems else { return ordered }
        return ordered.filter { !$0.isCompleted }
    }

    private var completedCount: Int {
        todoDocument.items.filter(\.isCompleted).count
    }

    private var totalCount: Int {
        todoDocument.items.count
    }

    private var selectedDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return L10n.SSHConnections.todoDateToday
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: selectedDate).capitalized
    }

    private var selectedDateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroCard
            controlBar
            if composerIsExpanded {
                composerCard
            }
            timelinePanel
            footer
        }
        .padding(18)
        .frame(width: 432)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .overlay(alignment: sidebarEdge == .leading ? .trailing : .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .animation(.snappy(duration: 0.22), value: composerIsExpanded)
        .animation(.snappy(duration: 0.22), value: editingItemID)
        .onAppear(perform: syncFromSettings)
        .onChange(of: store.configurationRevision) { _ in
            syncFromSettings()
        }
        .onChange(of: store.todoRevision) { _ in
            refreshDocument()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.SSHConnections.todoPanelTitle)
                    .font(.headline.weight(.semibold))

                Text(workspaceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                appDelegate.openTodoSettings(from: parentWindow)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.SSHConnections.todoPanelOpenSettings)

            Button {
                terminalController.todoSidebarIsPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.SSHConnections.todoPanelClose)
        }
    }

    private var heroCard: some View {
        let percentage = Int((todoDocument.completionRate * 100).rounded())

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDateTitle)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(selectedDateSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(percentage)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("\(completedCount) / \(max(totalCount, 0))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: todoDocument.completionRate)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack(spacing: 8) {
                    summaryPill("\(completedCount) complete", systemImage: "checkmark.circle.fill")
                    summaryPill("\(max(totalCount - completedCount, 0)) remaining", systemImage: "circle.dashed")
                    if !Calendar.current.isDateInToday(selectedDate) {
                        summaryPill(AITerminalTodoSettings.dayString(from: selectedDate), systemImage: "calendar")
                    }
                }
            }

            Text(L10n.SSHConnections.todoQuickLookSummary(
                summary.completedCount,
                summary.totalCount,
                summary.remainingCount
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                persistSelection()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .controlCapsule()

            Button(L10n.SSHConnections.todoDateToday) {
                selectedDate = .now
                persistSelection()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? Color.accentColor : Color.primary)
            .controlCapsule(isEmphasized: Calendar.current.isDateInToday(selectedDate))

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                persistSelection()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .controlCapsule()

            Spacer(minLength: 8)

            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: selectedDate) { _ in
                    persistSelection()
                }

            Button {
                composerIsExpanded = true
                composerTitleFieldFocused = true
            } label: {
                Label(L10n.SSHConnections.todoAddAction, systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .controlCapsule(isEmphasized: true)

            Menu {
                Button(showCompletedItems
                    ? L10n.SSHConnections.todoHideCompletedItems
                    : L10n.SSHConnections.todoShowCompletedItems) {
                    showCompletedItems.toggle()
                    persistSelection()
                }

                Divider()

                Button(L10n.SSHConnections.todoPanelOpenSettings) {
                    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                    appDelegate.openTodoSettings(from: parentWindow)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L10n.SSHConnections.todoAddAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    composerShowsNotes.toggle()
                } label: {
                    Label(L10n.SSHConnections.todoAddNotes, systemImage: composerShowsNotes ? "text.justify" : "note.text.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    composerIsExpanded = false
                    composerShowsNotes = false
                    draftTitle = ""
                    draftNotes = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            TextField(L10n.SSHConnections.todoAddTitle, text: $draftTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .focused($composerTitleFieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if composerShowsNotes {
                TextField(L10n.SSHConnections.todoAddNotes, text: $draftNotes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Text(L10n.SSHConnections.todoSelectedDay(AITerminalTodoSettings.dayString(from: selectedDate)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(L10n.SSHConnections.todoAddAction) {
                    guard let document = store.addTodoItem(
                        title: draftTitle,
                        notes: draftNotes,
                        for: selectedDate
                    ) else {
                        statusMessage = store.lastError
                        return
                    }

                    todoDocument = document
                    draftTitle = ""
                    draftNotes = ""
                    composerIsExpanded = false
                    composerShowsNotes = false
                    statusMessage = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.SSHConnections.todoTimelineTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(visibleTodoItems.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if visibleTodoItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(L10n.SSHConnections.todoEmpty)
                        .foregroundStyle(.secondary)

                    Button(L10n.SSHConnections.todoAddAction) {
                        composerIsExpanded = true
                        composerTitleFieldFocused = true
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleTodoItems, id: \.id) { item in
                            todoItemRow(item)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelSurface()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func todoItemRow(_ item: AITerminalTodoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    guard let document = store.setTodoItemCompleted(
                        id: item.id,
                        isCompleted: !item.isCompleted,
                        for: selectedDate
                    ) else {
                        statusMessage = store.lastError
                        return
                    }
                    todoDocument = document
                    statusMessage = nil
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    if editingItemID == item.id {
                        TextField(L10n.SSHConnections.todoAddTitle, text: $editingTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        TextField(L10n.SSHConnections.todoAddNotes, text: $editingNotes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                            .strikethrough(item.isCompleted, color: .secondary)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)

                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if editingItemID == item.id {
                        HStack(spacing: 8) {
                            Button(L10n.AITerminalManager.cancelEdit) {
                                editingItemID = nil
                                editingTitle = ""
                                editingNotes = ""
                            }
                            .buttonStyle(.bordered)

                            Button(L10n.SSHConnections.todoActionSave) {
                                guard let document = store.updateTodoItem(
                                    id: item.id,
                                    title: editingTitle,
                                    notes: editingNotes,
                                    for: selectedDate
                                ) else {
                                    statusMessage = store.lastError
                                    return
                                }
                                todoDocument = document
                                editingItemID = nil
                                editingTitle = ""
                                editingNotes = ""
                                statusMessage = nil
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        HStack(spacing: 8) {
                            metadataPill(todoTimelineLabel(for: item), systemImage: "clock")
                            todoAssignmentMenu(for: item)
                        }
                    }
                }

                Spacer(minLength: 8)

                if editingItemID != item.id {
                    Menu {
                        Button(L10n.SSHConnections.todoActionEdit) {
                            editingItemID = item.id
                            editingTitle = item.title
                            editingNotes = item.notes
                        }

                        if item.isCompleted {
                            Button(L10n.SSHConnections.todoActionReset) {
                                guard let document = store.setTodoItemCompleted(
                                    id: item.id,
                                    isCompleted: false,
                                    for: selectedDate
                                ) else {
                                    statusMessage = store.lastError
                                    return
                                }
                                todoDocument = document
                                statusMessage = nil
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(14)
        .subpanelSurface()
    }

    private func todoAssignmentMenu(for item: AITerminalTodoItem) -> some View {
        Menu {
            Button(L10n.SSHConnections.todoAssignmentClear) {
                assignTodoItem(item.id, to: nil)
            }

            if workspaceTargets.isEmpty {
                Text(L10n.SSHConnections.todoAssignmentNoTabs)
            } else {
                ForEach(workspaceTargets) { target in
                    Button(target.title) {
                        assignTodoItem(item.id, to: target.workspaceID)
                    }
                }
            }
        } label: {
            Label(todoAssignmentTitle(for: item), systemImage: "rectangle.stack.badge.person.crop")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    private func todoAssignmentTitle(for item: AITerminalTodoItem) -> String {
        guard let workspaceID = item.assignedWorkspaceID else {
            return L10n.SSHConnections.todoAssignmentUnassigned
        }
        return workspaceTargets.first(where: { $0.workspaceID == workspaceID })?.title
            ?? L10n.SSHConnections.todoAssignmentUnavailable
    }

    private func todoTimelineLabel(for item: AITerminalTodoItem) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let created = formatter.string(from: item.createdAt)
        if let completedAt = item.completedAt {
            return "Created \(created) · Completed \(formatter.string(from: completedAt))"
        }
        return "Created \(created)"
    }

    private func syncFromSettings() {
        let settings = store.todoSettings
        showCompletedItems = settings.showCompletedItems
        selectedDate = AITerminalTodoSettings.date(fromDayString: settings.selectedDateAnchor) ?? .now
        refreshDocument()
    }

    private func refreshDocument() {
        todoDocument = store.todoDocument(for: selectedDate)
    }

    private func persistSelection() {
        let settings = store.todoSettings
        store.saveTodoSettings(.init(
            enabled: settings.enabled,
            workspaceRootPath: settings.workspaceRootPath,
            showCompletedItems: showCompletedItems,
            selectedDateAnchor: AITerminalTodoSettings.dayString(from: selectedDate),
            sidebarEdge: settings.sidebarEdge,
            workspaceOverlayVisible: settings.workspaceOverlayVisible,
            workspaceOverlayCorner: settings.workspaceOverlayCorner
        ))
        statusMessage = store.lastError
        refreshDocument()
    }

    private func assignTodoItem(_ id: UUID, to workspaceID: UUID?) {
        guard let document = store.assignTodoItem(id: id, to: workspaceID, for: selectedDate) else {
            statusMessage = store.lastError
            return
        }
        todoDocument = document
        statusMessage = nil
    }

    private func summaryPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func metadataPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
    }
}

private extension View {
    func controlCapsule(isEmphasized: Bool = false) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (isEmphasized ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.06)),
                in: Capsule()
            )
    }
}

private extension AITerminalTodoSidebarEdge {
    var safeAreaEdge: HorizontalEdge {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}

private extension AITerminalTodoOverlayCorner {
    var alignment: Alignment {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

private struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugBuildWarningView: View {
    @State private var isPopover = false

    var body: some View {
        HStack {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(AppLocalization.localizedText("You're running a debug build of GhoDex! Performance will be degraded."))
                .padding(.all, 8)
                .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                    Text(AppLocalization.localizedText("Debug builds of GhoDex are very slow and you may experience performance problems. Debug builds are only recommended during development."))
                    .padding(.all)
                }

            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.localizedText("Debug build warning"))
        .accessibilityValue(AppLocalization.localizedText("Debug builds of GhoDex are very slow and you may experience performance problems. Debug builds are only recommended during development."))
        .accessibilityAddTraits(.isStaticText)
        .onTapGesture {
            isPopover = true
        }
    }
}
