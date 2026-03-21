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
                        parentWindow: terminalController.window
                    )
                }

                // Show update information above all else.
                if viewModel.updateOverlayIsVisible {
                    UpdateOverlay()
                }
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }
}

private struct TodoWorkspaceOverlay: View {
    @ObservedObject var store: AITerminalManagerStore

    let workspaceID: UUID
    let workspaceTitle: String
    weak var parentWindow: NSWindow?

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
        if store.todoSettings.enabled, summary.totalCount > 0 {
            VStack {
                Spacer()

                HStack(alignment: .bottom) {
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
                                appDelegate.showTodoWorkspace(
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

                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
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
