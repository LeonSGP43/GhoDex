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
    private enum ComposerFocusField: Hashable {
        case title
        case notes
    }

    @ObservedObject var store: AITerminalManagerStore
    @ObservedObject var terminalController: BaseTerminalController

    weak var parentWindow: NSWindow?
    let sidebarEdge: AITerminalTodoSidebarEdge

    @State private var selectedDate = Date.now
    @State private var showCompletedItems = true
    @State private var todoDocument = AITerminalTodoDayDocument()
    @State private var orderedTodoItems: [AITerminalTodoItem] = []
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var composerShowsNotes = false
    @State private var editingItemID: UUID?
    @State private var editingTitle = ""
    @State private var editingNotes = ""
    @State private var statusMessage: String?
    @State private var contentIsVisible = false
    @State private var composerFocusRequestID = UUID()
    @State private var syncableStaleTodoCount = 0
    @FocusState private var composerFocusField: ComposerFocusField?

    private static let sidebarAnimation = Animation.spring(response: 0.24, dampingFraction: 0.9)
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()
    private static let daySubtitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()
    private static let timelineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    private static let surfaceCornerRadius: CGFloat = 20

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
        let assigned = orderedTodoItems.filter { $0.assignedWorkspaceID == terminalController.workspaceID }
        return .init(
            workspaceID: terminalController.workspaceID,
            completedCount: assigned.filter(\.isCompleted).count,
            totalCount: assigned.count
        )
    }

    private var visibleTodoItems: [AITerminalTodoItem] {
        guard !showCompletedItems else { return orderedTodoItems }
        return orderedTodoItems.filter { !$0.isCompleted }
    }

    private var composerNeedsTitle: Bool {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDateIsToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return L10n.SSHConnections.todoDateToday
        }

        return Self.weekdayFormatter.string(from: selectedDate).capitalized
    }

    private var selectedDateSubtitle: String {
        return Self.daySubtitleFormatter.string(from: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            quickAddBar
            controlBar
            timelinePanel
            footer
        }
        .padding(18)
        .frame(width: 424)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .overlay(alignment: sidebarEdge == .leading ? .trailing : .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .opacity(contentIsVisible ? 1 : 0.001)
        .offset(x: contentIsVisible ? 0 : (sidebarEdge == .leading ? -14 : 14))
        .animation(Self.sidebarAnimation, value: contentIsVisible)
        .onAppear {
            syncFromSettings()
            withAnimation(Self.sidebarAnimation) {
                contentIsVisible = true
            }
            requestComposerFocus(.title)
        }
        .onDisappear {
            contentIsVisible = false
        }
        .onChange(of: store.configurationRevision) { _ in
            syncFromSettings()
        }
        .onChange(of: store.todoRevision) { _ in
            refreshDocument()
        }
        .onChange(of: draftTitle) { _ in
            clearComposerValidationIfNeeded()
        }
        .onChange(of: draftNotes) { _ in
            clearComposerValidationIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.SSHConnections.todoPanelTitle)
                    .font(.title3.weight(.semibold))

                Text(workspaceTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                appDelegate.openTodoSettings(from: parentWindow)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline.weight(.medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(0.03), in: Circle())
            .help(L10n.SSHConnections.todoPanelOpenSettings)

            Button {
                terminalController.todoSidebarIsPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(0.03), in: Circle())
            .help(L10n.SSHConnections.todoPanelClose)
        }
    }

    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                quickAddTitleField

                Button(action: addDraftItem) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)

                        Label(L10n.SSHConnections.todoAddAction, systemImage: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 132, height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if composerShowsNotes {
                quickAddNotesField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 10) {
                Text(L10n.SSHConnections.todoSelectedDay(AITerminalTodoSettings.dayString(from: selectedDate)))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    let willShowNotes = !composerShowsNotes
                    withAnimation(Self.sidebarAnimation) {
                        composerShowsNotes.toggle()
                    }
                    requestComposerFocus(willShowNotes ? .notes : .title)
                } label: {
                    Label(L10n.SSHConnections.todoAddNotes, systemImage: composerShowsNotes ? "text.justify" : "note.text.badge.plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(composerShowsNotes ? Color.accentColor : .secondary)
                .background((composerShowsNotes ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.045)), in: Capsule())
            }

            if composerNeedsTitle {
                Text(L10n.SSHConnections.todoTitleRequired)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .todoPanelSurface(cornerRadius: Self.surfaceCornerRadius)
    }

    private var quickAddTitleField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(composerNeedsTitle ? Color.red.opacity(0.85) : Color.clear, lineWidth: 1.5)

            TodoComposerTitleField(
                placeholder: L10n.SSHConnections.todoAddTitle,
                text: $draftTitle,
                isFocused: composerFocusField == .title,
                focusRequestID: composerFocusRequestID,
                onSubmit: addDraftItem,
                onShiftEnter: {
                    withAnimation(Self.sidebarAnimation) {
                        composerShowsNotes = true
                    }
                    requestComposerFocus(.notes)
                }
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            requestComposerFocus(.title)
        }
    }

    private var quickAddNotesField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))

            if draftNotes.isEmpty {
                Text(L10n.SSHConnections.todoAddNotes)
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }

            TodoComposerNotesField(
                text: $draftNotes,
                isFocused: composerFocusField == .notes,
                focusRequestID: composerFocusRequestID,
                onSubmit: addDraftItem
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 76)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            requestComposerFocus(.notes)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
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
            .font(.footnote.weight(.semibold))
            .foregroundStyle(selectedDateIsToday ? Color.accentColor : Color.primary)
            .controlCapsule(isEmphasized: selectedDateIsToday)

            if selectedDateIsToday {
                Button(action: syncStaleTodoPointersIntoToday) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text(L10n.SSHConnections.todoSyncStaleAction)
                        if syncableStaleTodoCount > 0 {
                            Text("\(syncableStaleTodoCount)")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(syncableStaleTodoCount > 0 ? Color.primary : .secondary)
                .controlCapsule(isEmphasized: syncableStaleTodoCount > 0)
                .disabled(syncableStaleTodoCount == 0)
            }

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
                .scaleEffect(0.94, anchor: .trailing)
                .onChange(of: selectedDate) { _ in
                    persistSelection()
                }

            Button {
                showCompletedItems.toggle()
                persistSelection()
            } label: {
                Image(systemName: showCompletedItems ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(showCompletedItems ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
                .help(showCompletedItems ? L10n.SSHConnections.todoHideCompletedItems : L10n.SSHConnections.todoShowCompletedItems)
        }
        .padding(.vertical, 2)
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.SSHConnections.todoTimelineTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(visibleTodoItems.count)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if visibleTodoItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(L10n.SSHConnections.todoEmpty)
                        .foregroundStyle(.secondary)

                    Button(L10n.SSHConnections.todoAddAction) {
                        requestComposerFocus(.title)
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
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        let percentage = Int((todoDocument.completionRate * 100).rounded())

        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDateTitle)
                        .font(.headline.weight(.semibold))

                    Text(selectedDateSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(L10n.SSHConnections.todoQuickLookSummary(
                    summary.completedCount,
                    summary.totalCount,
                    summary.remainingCount
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("\(percentage)%")
                    .font(.headline.weight(.bold))
            }

            ProgressView(value: todoDocument.completionRate)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func todoItemRow(_ item: AITerminalTodoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Button(
                    action: { toggleCompletion(for: item, isCompleted: !item.isCompleted) },
                    label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? Color.green : Color.accentColor)
                            .font(.title2.weight(.semibold))
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill((item.isCompleted ? Color.green : Color.accentColor).opacity(0.12))
                            )
                    }
                )
                .buttonStyle(.plain)
                .contentShape(Circle())

                VStack(alignment: .leading, spacing: 10) {
                    if editingItemID == item.id {
                        TextField(L10n.SSHConnections.todoAddTitle, text: $editingTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        TextField(L10n.SSHConnections.todoAddNotes, text: $editingNotes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .strikethrough(item.isCompleted, color: .secondary)
                            .foregroundStyle(item.isCompleted ? Color.primary.opacity(0.62) : .primary)
                            .lineLimit(3)

                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.body)
                                .foregroundStyle(item.isCompleted ? Color.secondary.opacity(0.85) : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(4)
                        }

                        if let stalePointerLabel = todoStalePointerLabel(for: item) {
                            metadataText(stalePointerLabel, systemImage: "arrow.turn.down.right")
                        }

                        metadataText(todoTimelineLabel(for: item), systemImage: "clock")
                    }
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
                HStack(alignment: .center, spacing: 8) {
                    todoInlineActionButton(
                        title: item.isCompleted ? L10n.SSHConnections.todoActionReset : L10n.SSHConnections.todoActionComplete,
                        systemImage: item.isCompleted ? "arrow.counterclockwise" : "checkmark",
                        isEmphasized: true
                    ) {
                        toggleCompletion(for: item, isCompleted: !item.isCompleted)
                    }

                    todoInlineActionButton(title: L10n.SSHConnections.todoActionEdit, systemImage: "square.and.pencil") {
                        editingItemID = item.id
                        editingTitle = item.title
                        editingNotes = item.notes
                    }

                    todoAssignmentMenu(for: item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(todoCardBackground(for: item), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(todoCardBorder(for: item), lineWidth: item.isCompleted ? 1 : 1.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(todoCardBorder(for: item))
                .frame(width: 4)
                .padding(.vertical, 10)
        }
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
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.footnote)
                Text(todoAssignmentTitle(for: item))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.045), in: Capsule())
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
        let created = Self.timelineFormatter.string(from: item.createdAt)
        if let completedAt = item.completedAt {
            return L10n.SSHConnections.todoTimelineCreatedCompleted(
                created,
                Self.timelineFormatter.string(from: completedAt)
            )
        }
        return L10n.SSHConnections.todoTimelineCreated(created)
    }

    private func todoStalePointerLabel(for item: AITerminalTodoItem) -> String? {
        guard let sourceReference = item.sourceItem else { return nil }
        guard let sourceDate = AITerminalTodoSettings.date(fromDayString: sourceReference.day) else {
            return L10n.SSHConnections.todoStalePointer(sourceReference.day)
        }
        return L10n.SSHConnections.todoStalePointer(Self.daySubtitleFormatter.string(from: sourceDate))
    }

    private func syncFromSettings() {
        let settings = store.todoSettings
        showCompletedItems = settings.showCompletedItems
        selectedDate = AITerminalTodoSettings.date(fromDayString: settings.selectedDateAnchor) ?? .now
        refreshDocument()
    }

    private func refreshDocument() {
        let document = store.todoDocument(for: selectedDate)
        todoDocument = document
        orderedTodoItems = document.orderedItems
        refreshStaleTodoSyncState()
    }

    private func addDraftItem() {
        if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = L10n.SSHConnections.todoTitleRequired
            requestComposerFocus(.title)
            return
        }

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
        composerShowsNotes = false
        statusMessage = nil
        requestComposerFocus(.title)
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

    private func clearComposerValidationIfNeeded() {
        if !composerNeedsTitle && statusMessage == L10n.SSHConnections.todoTitleRequired {
            statusMessage = nil
        }
    }

    private func refreshStaleTodoSyncState() {
        syncableStaleTodoCount = selectedDateIsToday ? store.syncableStaleTodoPointerCount(into: selectedDate) : 0
    }

    private func requestComposerFocus(_ field: ComposerFocusField) {
        composerFocusField = field
        composerFocusRequestID = UUID()
    }

    private func syncStaleTodoPointersIntoToday() {
        guard let syncedCount = store.syncIncompleteTodoPointers(into: selectedDate) else {
            statusMessage = store.lastError
            return
        }

        statusMessage = syncedCount > 0
            ? L10n.SSHConnections.todoSyncStaleSuccess(syncedCount)
            : L10n.SSHConnections.todoSyncStaleEmpty
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

    private func toggleCompletion(for item: AITerminalTodoItem, isCompleted: Bool) {
        guard let document = store.setTodoItemCompleted(
            id: item.id,
            isCompleted: isCompleted,
            for: selectedDate
        ) else {
            statusMessage = store.lastError
            return
        }
        todoDocument = document
        statusMessage = nil
    }

    private func metadataText(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func todoInlineActionButton(
        title: String,
        systemImage: String,
        isEmphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEmphasized ? Color.accentColor : .secondary)
        .background(
            (isEmphasized ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.045)),
            in: Capsule()
        )
    }

    private func todoCardBackground(for item: AITerminalTodoItem) -> Color {
        if item.isCompleted {
            return Color.green.opacity(0.06)
        }
        if item.isCarryForwardPointer {
            return Color.orange.opacity(0.045)
        }
        return Color.white.opacity(0.025)
    }

    private func todoCardBorder(for item: AITerminalTodoItem) -> Color {
        if item.isCompleted {
            return Color.green.opacity(0.32)
        }
        if item.isCarryForwardPointer {
            return Color.orange.opacity(0.2)
        }
        return Color.white.opacity(0.08)
    }
}

private struct TodoComposerTitleField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onShiftEnter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onShiftEnter: onShiftEnter)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .title2).pointSize,
            weight: .semibold
        )
        field.placeholderString = placeholder
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        context.coordinator.textField = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onShiftEnter = onShiftEnter
        context.coordinator.focusRequestID = focusRequestID

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard isFocused else { return }
        DispatchQueue.main.async {
            guard context.coordinator.lastAppliedFocusRequestID != focusRequestID else { return }
            guard let window = nsView.window else { return }
            if window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
            guard let editor = nsView.currentEditor() as? NSTextView else { return }
            let insertionPoint = NSRange(location: nsView.stringValue.count, length: 0)
            if editor.selectedRange() != insertionPoint {
                editor.setSelectedRange(insertionPoint)
            }
            context.coordinator.lastAppliedFocusRequestID = focusRequestID
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onShiftEnter: () -> Void
        var focusRequestID = UUID()
        var lastAppliedFocusRequestID: UUID?
        weak var textField: NSTextField?

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onShiftEnter: @escaping () -> Void
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onShiftEnter = onShiftEnter
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard control === textField else { return false }

            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                onShiftEnter()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    onShiftEnter()
                } else {
                    onSubmit()
                }
                return true
            }

            return false
        }
    }
}

private struct TodoComposerNotesField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let focusRequestID: UUID
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.focusRequestID = focusRequestID

        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        guard isFocused else { return }
        context.coordinator.scheduleFocusAttempt()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var focusRequestID = UUID()
        var lastAppliedFocusRequestID: UUID?
        weak var textView: NSTextView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func scheduleFocusAttempt(remainingAttempts: Int = 8) {
            DispatchQueue.main.async { [weak self] in
                self?.applyFocus(remainingAttempts: remainingAttempts)
            }
        }

        private func applyFocus(remainingAttempts: Int) {
            guard lastAppliedFocusRequestID != focusRequestID else { return }
            guard let textView else { return }
            guard let window = textView.window else {
                if remainingAttempts > 0 {
                    scheduleFocusAttempt(remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            if window.firstResponder !== textView && !window.makeFirstResponder(textView) {
                if remainingAttempts > 0 {
                    scheduleFocusAttempt(remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            let insertionPoint = NSRange(location: textView.string.count, length: 0)
            if textView.selectedRange() != insertionPoint {
                textView.setSelectedRange(insertionPoint)
            }
            lastAppliedFocusRequestID = focusRequestID
        }

        private func insertPlainNewline(into textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard textView.shouldChangeText(in: selectedRange, replacementString: "\n") else { return }
            textView.textStorage?.replaceCharacters(in: selectedRange, with: "\n")
            let nextLocation = selectedRange.location + 1
            textView.setSelectedRange(NSRange(location: nextLocation, length: 0))
            textView.didChangeText()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                insertPlainNewline(into: textView)
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    insertPlainNewline(into: textView)
                } else {
                    onSubmit()
                }
                return true
            }

            return false
        }
    }
}

private extension View {
    func todoPanelSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(Color.white.opacity(0.026), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    func controlCapsule(isEmphasized: Bool = false) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (isEmphasized ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.038)),
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
