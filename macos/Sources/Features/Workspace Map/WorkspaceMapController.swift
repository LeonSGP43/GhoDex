import AppKit
import SwiftUI
import Combine
import GhoDexKit

@MainActor
final class WorkspaceMapViewModel: ObservableObject {
    @Published private(set) var snapshot = WorkspaceMapSnapshot(groups: [])
    @Published private(set) var layout: WorkspaceMapLayoutSnapshot
    @Published private(set) var performance = WorkspaceMapPerformanceSnapshot.empty
    @Published private(set) var lastCommandResult: WorkspaceMapCommandResult?
    @Published private(set) var isCanvasPresentationActive = false

    private let projectionSource: (() -> WorkspaceMapSnapshot)?
    private let runtimeStateSource: (@MainActor () -> WorkspaceMapRuntimeState)?
    private let backgroundProjector: @Sendable (WorkspaceMapRuntimeState, Date) -> WorkspaceMapSnapshot
    private let commandExecutor: (WorkspaceMapCommandRequest) -> WorkspaceMapCommandResult
    private let layoutStore: WorkspaceMapLayoutStore
    private let nowProvider: () -> Date

    private var refreshScheduled = false
    private var refreshInFlight = false
    private var refreshPending = false
    private var refreshTask: Task<Void, Never>?
    private var latestRefreshGeneration: UInt64 = 0
    private var latestAppliedCaptureSequence: UInt64?
    private var layoutPersistScheduled = false
    private var performanceRecorder = WorkspaceMapPerformanceRecorder()
    private var workloadClassifier = WorkspaceMapWorkloadClassifier()

    @available(*, deprecated, message: "Use runtimeStateSource/backgroundProjector path for better performance")
    init(
        projectionSource: @escaping () -> WorkspaceMapSnapshot,
        commandExecutor: @escaping (WorkspaceMapCommandRequest) -> WorkspaceMapCommandResult,
        layoutStore: WorkspaceMapLayoutStore = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.projectionSource = projectionSource
        self.runtimeStateSource = nil
        self.backgroundProjector = { runtimeState, now in
            WorkspaceMapProjectionService.makeSnapshot(from: runtimeState, now: now)
        }
        self.commandExecutor = commandExecutor
        self.layoutStore = layoutStore
        self.nowProvider = nowProvider
        self.layout = layoutStore.load() ?? WorkspaceMapLayoutSnapshot(groups: [])
    }

    deinit {
        refreshTask?.cancel()
    }

    init(
        runtimeStateSource: @escaping @MainActor () -> WorkspaceMapRuntimeState,
        backgroundProjector: @escaping @Sendable (WorkspaceMapRuntimeState, Date) -> WorkspaceMapSnapshot = { runtimeState, now in
            WorkspaceMapProjectionService.makeSnapshot(from: runtimeState, now: now)
        },
        commandExecutor: @escaping (WorkspaceMapCommandRequest) -> WorkspaceMapCommandResult,
        layoutStore: WorkspaceMapLayoutStore = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.projectionSource = nil
        self.runtimeStateSource = runtimeStateSource
        self.backgroundProjector = backgroundProjector
        self.commandExecutor = commandExecutor
        self.layoutStore = layoutStore
        self.nowProvider = nowProvider
        self.layout = layoutStore.load() ?? WorkspaceMapLayoutSnapshot(groups: [])
    }

    convenience init(
        layoutStore: WorkspaceMapLayoutStore = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            runtimeStateSource: { WorkspaceMapRuntimeAdapter.capture() },
            commandExecutor: { WorkspaceMapCommandHandler.execute($0) },
            layoutStore: layoutStore,
            nowProvider: nowProvider
        )
    }

    var viewportOffset: CGSize {
        CGSize(width: layout.viewport.offsetX, height: layout.viewport.offsetY)
    }

    var zoomScale: CGFloat {
        CGFloat(layout.viewport.zoom)
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        latestRefreshGeneration &+= 1
        let refreshGeneration = latestRefreshGeneration

        if let projectionSource {
            let start = CFAbsoluteTimeGetCurrent()
            let newSnapshot = projectionSource()
            let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            applyRefresh(newSnapshot, totalMS: elapsedMS, mainThreadMS: elapsedMS)
            return nil
        }

        guard let runtimeStateSource else { return nil }
        guard !refreshInFlight else {
            refreshPending = true
            return refreshTask
        }

        refreshInFlight = true
        let start = CFAbsoluteTimeGetCurrent()
        let runtimeState = runtimeStateSource()
        let mainThreadMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let snapshotNow = nowProvider()
        let captureSequence = runtimeState.captureSequence
        let projector = backgroundProjector
        let task = Task { [weak self, runtimeState, captureSequence, refreshGeneration, mainThreadMS, snapshotNow, start] in
            let newSnapshot = await Task.detached(priority: .userInitiated) {
                projector(runtimeState, snapshotNow)
            }.value
            guard !Task.isCancelled else { return }
            let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            self?.finishRefresh(
                newSnapshot,
                captureSequence: captureSequence,
                refreshGeneration: refreshGeneration,
                totalMS: elapsedMS,
                mainThreadMS: mainThreadMS
            )
        }
        refreshTask = task
        return task
    }

    private func finishRefresh(
        _ newSnapshot: WorkspaceMapSnapshot,
        captureSequence: UInt64,
        refreshGeneration: UInt64,
        totalMS: Double,
        mainThreadMS: Double
    ) {
        defer {
            refreshInFlight = false
            refreshTask = nil

            if refreshPending {
                refreshPending = false
                _ = refresh()
            }
        }

        guard refreshGeneration == latestRefreshGeneration else { return }
        let hasMonotonicCaptureSequence = captureSequence > 0
        if hasMonotonicCaptureSequence {
            guard latestAppliedCaptureSequence.map({ captureSequence > $0 }) ?? true else { return }
        }

        applyRefresh(newSnapshot, totalMS: totalMS, mainThreadMS: mainThreadMS)
        if hasMonotonicCaptureSequence {
            latestAppliedCaptureSequence = captureSequence
        }
    }

    private func applyRefresh(
        _ newSnapshot: WorkspaceMapSnapshot,
        totalMS: Double,
        mainThreadMS: Double
    ) {
        let now = nowProvider()
        workloadClassifier.recordRefresh(at: now)
        let workload = workloadClassifier.classify(snapshot: newSnapshot, at: now)

        performanceRecorder.recordSnapshotBuild(
            ms: totalMS,
            mainThreadMS: mainThreadMS,
            workload: workload
        )
        if !newSnapshot.semanticallyEquals(snapshot) {
            snapshot = newSnapshot
            reconcileLayout(with: newSnapshot.groups)
            performanceRecorder.recordPublish(at: now, workload: workload)
        }

        publishPerformance()
    }

    func scheduleRefresh() {
        workloadClassifier.recordRefreshRequest(at: nowProvider())
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    @discardableResult
    func execute(
        _ command: WorkspaceMapCommand,
        targetID: WorkspaceMapEntityID,
        title: String? = nil
    ) -> Task<Void, Never>? {
        let request = WorkspaceMapCommandRequest(command: command, targetID: targetID, title: title)
        let start = CFAbsoluteTimeGetCurrent()
        let result = commandExecutor(request)
        lastCommandResult = result
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let now = nowProvider()
        workloadClassifier.recordCommand(at: now)
        let workload = workloadClassifier.classify(snapshot: snapshot, at: now)
        performanceRecorder.recordCommandLatency(ms: elapsedMS, workload: workload)
        performanceRecorder.recordCommandStatus(result.status, workload: workload)
        publishPerformance()
        return refresh()
    }

    func setViewportOffset(_ offset: CGSize) {
        mutateLayout { layout in
            layout.viewport.offsetX = offset.width
            layout.viewport.offsetY = offset.height
        }
    }

    func setZoom(_ zoom: CGFloat) {
        mutateLayout { layout in
            layout.viewport.zoom = min(max(Double(zoom), 0.45), 2.2)
        }
    }

    func adjustZoom(delta: CGFloat) {
        setZoom(zoomScale + delta)
    }

    func resetViewport() {
        mutateLayout { layout in
            layout.viewport = .default
        }
    }

    func setCanvasPresentationActive(_ isActive: Bool) {
        guard isCanvasPresentationActive != isActive else { return }
        isCanvasPresentationActive = isActive
    }

    func groupPosition(for groupID: WorkspaceMapEntityID) -> CGPoint {
        guard let group = layout.groups.first(where: { $0.id == groupID }) else {
            return .init(x: 160, y: 120)
        }
        return .init(x: group.centerX, y: group.centerY)
    }

    func isGroupCollapsed(_ groupID: WorkspaceMapEntityID) -> Bool {
        layout.groups.first(where: { $0.id == groupID })?.isCollapsed ?? false
    }

    func toggleGroupCollapsed(_ groupID: WorkspaceMapEntityID) {
        mutateGroupLayout(groupID) { group in
            group.isCollapsed.toggle()
        }
    }

    func setGroupPosition(_ groupID: WorkspaceMapEntityID, point: CGPoint) {
        mutateGroupLayout(groupID) { group in
            group.centerX = point.x
            group.centerY = point.y
        }
    }

    func autoLayoutGroups() {
        let groups = snapshot.groups
        guard !groups.isEmpty else { return }

        var terminalIndex = 0
        var browserIndex = 0
        mutateLayout { layout in
            layout.groups = groups.map { group in
                let existing = layout.groups.first(where: { $0.id == group.id })
                let index = group.kind == .terminal ? terminalIndex : browserIndex
                if group.kind == .terminal {
                    terminalIndex += 1
                } else {
                    browserIndex += 1
                }
                let defaultPoint = Self.defaultGroupPosition(kind: group.kind, index: index)
                return WorkspaceMapGroupLayoutSnapshot(
                    id: group.id,
                    centerX: defaultPoint.x,
                    centerY: defaultPoint.y,
                    isCollapsed: existing?.isCollapsed ?? false
                )
            }
        }
    }

    private func reconcileLayout(with groups: [WorkspaceMapGroupSnapshot]) {
        var terminalIndex = 0
        var browserIndex = 0

        mutateLayout(persist: false) { layout in
            let oldByID = Dictionary(uniqueKeysWithValues: layout.groups.map { ($0.id, $0) })
            let merged: [WorkspaceMapGroupLayoutSnapshot] = groups.map { group in
                if let existing = oldByID[group.id] {
                    return existing
                }

                let index = group.kind == .terminal ? terminalIndex : browserIndex
                if group.kind == .terminal {
                    terminalIndex += 1
                } else {
                    browserIndex += 1
                }

                let defaultPoint = Self.defaultGroupPosition(kind: group.kind, index: index)
                return WorkspaceMapGroupLayoutSnapshot(
                    id: group.id,
                    centerX: defaultPoint.x,
                    centerY: defaultPoint.y,
                    isCollapsed: false
                )
            }
            layout.groups = merged
        }
        scheduleLayoutPersist()
    }

    private func mutateGroupLayout(
        _ groupID: WorkspaceMapEntityID,
        mutate: (inout WorkspaceMapGroupLayoutSnapshot) -> Void
    ) {
        mutateLayout { layout in
            guard let index = layout.groups.firstIndex(where: { $0.id == groupID }) else { return }
            var group = layout.groups[index]
            mutate(&group)
            layout.groups[index] = group
        }
    }

    private func mutateLayout(
        persist: Bool = true,
        mutate: (inout WorkspaceMapLayoutSnapshot) -> Void
    ) {
        var nextLayout = layout
        mutate(&nextLayout)
        guard nextLayout != layout else { return }
        layout = nextLayout
        if persist {
            scheduleLayoutPersist()
        }
    }

    private func scheduleLayoutPersist() {
        guard !layoutPersistScheduled else { return }
        layoutPersistScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.layoutPersistScheduled = false
            self.layoutStore.save(self.layout)
        }
    }

    private func publishPerformance() {
        performance = performanceRecorder.snapshot()
    }

    private static func defaultGroupPosition(kind: WorkspaceMapGroupKind, index: Int) -> CGPoint {
        let columns = 3
        let col = index % columns
        let row = index / columns
        let originX = kind == .terminal ? 260.0 : 1320.0
        let x = originX + Double(col) * 360
        let y = 180.0 + Double(row) * 260
        return CGPoint(x: x, y: y)
    }
}

struct WorkspaceMapView: View {
    @ObservedObject var model: WorkspaceMapViewModel
    let contentProvider: WorkspaceMapLiveCanvasContentProvider

    var body: some View {
        ZStack {
            WorkspaceMapCanvasBackground()
                .ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.snapshot.groups, id: \.id) { group in
                        WorkspaceMapFallbackGroupRow(model: model, group: group)
                    }
                }
                .padding(16)
            }
            if model.snapshot.groups.isEmpty {
                Text(AppLocalization.localizedText("No top-level tabs available."))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            model.scheduleRefresh()
        }
    }
}

private struct WorkspaceMapFallbackGroupRow: View {
    @ObservedObject var model: WorkspaceMapViewModel
    let group: WorkspaceMapGroupSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(group.kind.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let terminal = group.terminal {
                Text("splits \(terminal.splitCount) | panes \(terminal.paneCount) | tabs \(terminal.tabCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let browser = group.browser {
                Text(browser.displayedURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(AppLocalization.localizedText("Focus")) {
                    _ = model.execute(.focusTopLevelGroup, targetID: group.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(AppLocalization.localizedText("Close")) {
                    _ = model.execute(.closeTopLevelGroup, targetID: group.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let activePaneTabID = group.terminal?.nodes.first(where: { $0.kind == .paneTab && $0.isActive })?.id {
                    Button(AppLocalization.localizedText("Jump Active Tab")) {
                        _ = model.execute(.jumpToTerminalPaneTab, targetID: activePaneTabID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(group.isFocused ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(group.isFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WorkspaceMapSnapshotScale {
    let totalGroups: Int
    let totalPanes: Int
    let totalTabs: Int
}

private extension WorkspaceMapSnapshot {
    var performanceScale: WorkspaceMapSnapshotScale {
        let totalPanes = groups.reduce(into: 0) { partial, group in
            partial += group.terminal?.paneCount ?? 0
        }
        let totalTabs = groups.reduce(into: 0) { partial, group in
            partial += group.terminal?.tabCount ?? 0
        }

        return WorkspaceMapSnapshotScale(
            totalGroups: groups.count,
            totalPanes: totalPanes,
            totalTabs: totalTabs
        )
    }
}

private struct WorkspaceMapWorkloadClassifier {
    private static let largeBWindowSeconds: TimeInterval = 10
    private static let largeBRefreshThreshold = 200
    private static let largeCWindowSeconds: TimeInterval = 5
    private static let largeCCommandThreshold = 10
    private static let largeAGroupThreshold = 20
    private static let largeAPaneThreshold = 120
    private static let largeATabThreshold = 360

    private var refreshRequestTimestamps: [Date] = []
    private var refreshExecutionTimestamps: [Date] = []
    private var commandTimestamps: [Date] = []

    mutating func recordRefreshRequest(at date: Date) {
        refreshRequestTimestamps.append(date)
        trim(reference: date)
    }

    mutating func recordRefresh(at date: Date) {
        refreshExecutionTimestamps.append(date)
        trim(reference: date)
    }

    mutating func recordCommand(at date: Date) {
        commandTimestamps.append(date)
        trim(reference: date)
    }

    mutating func classify(snapshot: WorkspaceMapSnapshot, at date: Date) -> WorkspaceMapPerformanceWorkload? {
        trim(reference: date)

        if commandTimestamps.count >= Self.largeCCommandThreshold {
            return .largeC
        }

        if refreshRequestTimestamps.count >= Self.largeBRefreshThreshold {
            return .largeB
        }

        let scale = snapshot.performanceScale
        if scale.totalGroups >= Self.largeAGroupThreshold &&
            scale.totalPanes >= Self.largeAPaneThreshold &&
            scale.totalTabs >= Self.largeATabThreshold {
            return .largeA
        }

        return nil
    }

    private mutating func trim(reference date: Date) {
        let largeBCutoff = date.addingTimeInterval(-Self.largeBWindowSeconds)
        refreshRequestTimestamps.removeAll { $0 < largeBCutoff }
        refreshExecutionTimestamps.removeAll { $0 < largeBCutoff }

        let largeCCutoff = date.addingTimeInterval(-Self.largeCWindowSeconds)
        commandTimestamps.removeAll { $0 < largeCCutoff }
    }
}

private struct WorkspaceMapCanvasBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor).opacity(0.85),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    let step: CGFloat = 52
                    let width = geometry.size.width
                    let height = geometry.size.height

                    var x: CGFloat = 0
                    while x <= width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                        x += step
                    }

                    var y: CGFloat = 0
                    while y <= height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        y += step
                    }
                }
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct WorkspaceMapGroupCard: View {
    let group: WorkspaceMapGroupSnapshot
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onFocus: () -> Void
    let onRename: () -> Void
    let onClose: () -> Void
    let onJumpToPaneTab: (WorkspaceMapEntityID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(group.kind.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isCollapsed ? AppLocalization.localizedText("Expand") : AppLocalization.localizedText("Collapse")) {
                    onToggleCollapse()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if !isCollapsed {
                if let terminal = group.terminal {
                    Text("splits \(terminal.splitCount) | panes \(terminal.paneCount) | tabs \(terminal.tabCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let activePaneTab = terminal.nodes.first(where: { $0.kind == .paneTab && $0.isActive }) {
                        Button(AppLocalization.localizedText("Jump Active Tab")) {
                            onJumpToPaneTab(activePaneTab.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    WorkspaceMapHierarchyMiniView(terminal: terminal)
                }

                if let browser = group.browser {
                    Text(browser.displayedURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(AppLocalization.localizedText("Focus")) {
                    onFocus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(AppLocalization.localizedText("Rename")) {
                    onRename()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(AppLocalization.localizedText("Close")) {
                    onClose()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(group.isFocused ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(group.isFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
    }
}

private struct WorkspaceMapHierarchyMiniView: View {
    let terminal: WorkspaceMapTerminalGroupSnapshot

    var body: some View {
        let lines = makeLines(maxDepth: 3, maxLines: 14)
        if lines.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func makeLines(maxDepth: Int, maxLines: Int) -> [String] {
        guard let rootID = terminal.rootNodeID else { return [] }
        let nodeByID = Dictionary(uniqueKeysWithValues: terminal.nodes.map { ($0.id, $0) })
        var lines: [String] = []

        func visit(_ nodeID: WorkspaceMapEntityID, depth: Int) {
            guard lines.count < maxLines else { return }
            guard depth <= maxDepth else { return }
            guard let node = nodeByID[nodeID] else { return }

            let indent = String(repeating: "  ", count: depth)
            let marker = node.isActive ? "*" : "-"
            let descriptor: String
            switch node.kind {
            case .split:
                let direction = node.splitDirection?.rawValue ?? "?"
                let ratio = node.splitRatio.map { String(format: "%.2f", $0) } ?? "-"
                descriptor = "split \(direction) \(ratio)"
            case .pane:
                descriptor = "pane"
            case .paneTab:
                descriptor = "tab \(node.title)"
            }
            lines.append("\(indent)\(marker) \(descriptor)")

            for childID in node.childIDs {
                visit(childID, depth: depth + 1)
            }
        }

        visit(rootID, depth: 0)
        return lines
    }
}

final class WorkspaceMapController: NSWindowController, NSWindowDelegate, TopLevelTabController {
    static var all: [WorkspaceMapController] {
        NSApplication.shared.windows.compactMap { $0.windowController as? WorkspaceMapController }
    }

    private let ghostty: Ghostty.App
    private let viewModel = WorkspaceMapViewModel()
    private let liveCanvasContentProvider: WorkspaceMapLiveCanvasContentProvider = WorkspaceMapRuntimeLiveCanvasContentProvider()
    private var windowLifecycleCancellables: Set<AnyCancellable> = []
    private var windowContentConfigured = false

    var titleOverride: String? {
        didSet {
            applyWindowTitle()
        }
    }

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalization.localizedText("Workspace Map")
        window.tabbingMode = .preferred
        window.isRestorable = false
        super.init(window: window)
        configureWindowIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WorkspaceMapController")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        configureWindowIfNeeded()
    }

    override func showWindow(_ sender: Any?) {
        configureWindowIfNeeded()
        super.showWindow(sender)
        viewModel.setCanvasPresentationActive(true)
        viewModel.scheduleRefresh()
        applyWindowTitle()
    }

    func promptTabTitle() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = AppLocalization.localizedText("Rename Tab")
        alert.informativeText = AppLocalization.localizedText("Enter a custom title for this workspace map tab.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.App.ok)
        alert.addButton(withTitle: L10n.App.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = titleOverride ?? AppLocalization.localizedText("Workspace Map")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let newValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.titleOverride = newValue.isEmpty ? nil : newValue
        }
    }

    func closeTabImmediately(registerRedo: Bool = true) {
        window?.close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setCanvasPresentationActive(true)
        viewModel.scheduleRefresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setCanvasPresentationActive(false)
    }

    static func newWindow(
        _ ghostty: Ghostty.App,
        withParent explicitParent: NSWindow? = nil
    ) -> WorkspaceMapController {
        let controller = WorkspaceMapController(ghostty)
        let parent = explicitParent ?? preferredParentWindow()

        DispatchQueue.main.async {
            if let parent,
               let window = controller.window,
               !parent.styleMask.contains(.fullScreen),
               window.tabGroup?.windows.count ?? 1 == 1 {
                _ = window.cascadeTopLeft(from: NSPoint(x: parent.frame.minX, y: parent.frame.maxY))
            }
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }

    static func newTab(
        _ ghostty: Ghostty.App,
        from parent: NSWindow? = nil
    ) -> WorkspaceMapController {
        let controller = WorkspaceMapController(ghostty)
        guard let window = controller.window else { return controller }

        if let parent {
            if parent.isMiniaturized {
                parent.deminiaturize(nil)
            }
            if let tabGroup = parent.tabGroup,
               tabGroup.windows.contains(where: { $0 === window }) {
                tabGroup.removeWindow(window)
            }
            if window.tabbingMode != .disallowed {
                parent.addTabbedWindowSafely(window, ordered: .above)
            }
        }

        DispatchQueue.main.async {
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }

    static func preferredParentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? TerminalController.preferredParent?.window
    }

    static func closeAllWindowsImmediately() {
        all.forEach { $0.window?.close() }
    }

    private func applyWindowTitle() {
        let title = titleOverride ?? AppLocalization.localizedText("Workspace Map")
        window?.title = title
        (window as? TerminalWindow)?.title = title
    }

    private func configureWindowIfNeeded() {
        guard !windowContentConfigured, let window else { return }
        window.delegate = self
        window.contentView = NSHostingView(rootView: WorkspaceMapView(model: viewModel, contentProvider: liveCanvasContentProvider))
        windowContentConfigured = true
        applyWindowTitle()
        setupWindowLifecycleRefresh()
    }

    private func setupWindowLifecycleRefresh() {
        windowLifecycleCancellables.removeAll()

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: nil)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.setCanvasPresentationActive(false)
                self?.viewModel.scheduleRefresh()
            }
            .store(in: &windowLifecycleCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification, object: nil)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.scheduleRefresh()
            }
            .store(in: &windowLifecycleCancellables)
    }
}
