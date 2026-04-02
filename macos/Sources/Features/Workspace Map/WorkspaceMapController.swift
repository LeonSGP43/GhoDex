import AppKit
import SwiftUI
import Combine
import GhoDexKit

@MainActor
final class WorkspaceMapViewModel: ObservableObject {
    private static let canvasFocusedRefreshInterval: TimeInterval = 0.2
    private static let canvasBackgroundRefreshInterval: TimeInterval = 0.25

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
    private var activeRefreshTimer: Timer?
    private var activeRefreshTimerInterval: TimeInterval?
    private var isCanvasWindowKey = true
    private var layoutPersistScheduled = false
    private var groupBaseSizeHints: [WorkspaceMapEntityID: CGSize] = [:]
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
        activeRefreshTimer?.invalidate()
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
        if isActive {
            startActiveRefreshTicker()
            scheduleRefresh()
        } else {
            stopActiveRefreshTicker()
        }
    }

    func setCanvasWindowKeyState(_ isKey: Bool) {
        guard isCanvasWindowKey != isKey else { return }
        isCanvasWindowKey = isKey
        guard isCanvasPresentationActive else { return }
        if isKey {
            scheduleRefresh()
        }
    }

    @objc
    private func handleActiveRefreshTimer(_ timer: Timer) {
        guard timer === activeRefreshTimer else { return }
        guard isCanvasPresentationActive else {
            stopActiveRefreshTicker()
            return
        }
        let expectedInterval = preferredActiveRefreshInterval()
        if let currentInterval = activeRefreshTimerInterval,
           abs(expectedInterval - currentInterval) > 0.001 {
            activeRefreshTimerInterval = expectedInterval
            scheduleActiveRefreshTimer()
        }
        scheduleRefresh()
    }

    private func startActiveRefreshTicker() {
        guard activeRefreshTimer == nil else { return }
        activeRefreshTimerInterval = preferredActiveRefreshInterval()
        scheduleActiveRefreshTimer()
    }

    private func stopActiveRefreshTicker() {
        activeRefreshTimer?.invalidate()
        activeRefreshTimer = nil
        activeRefreshTimerInterval = nil
    }

    private func preferredActiveRefreshInterval() -> TimeInterval {
        isCanvasWindowKey ? Self.canvasFocusedRefreshInterval : Self.canvasBackgroundRefreshInterval
    }

    private func scheduleActiveRefreshTimer() {
        activeRefreshTimer?.invalidate()
        let interval = activeRefreshTimerInterval ?? preferredActiveRefreshInterval()
        let timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleActiveRefreshTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        activeRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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

    func updateGroupBaseSizeHint(_ groupID: WorkspaceMapEntityID, size: CGSize) {
        let normalized = CGSize(
            width: max(size.width, 520),
            height: max(size.height, 320)
        )
        if let existing = groupBaseSizeHints[groupID],
           abs(existing.width - normalized.width) < 0.5,
           abs(existing.height - normalized.height) < 0.5 {
            return
        }
        groupBaseSizeHints[groupID] = normalized
    }

    func autoLayoutGroups() {
        let groups = snapshot.groups
        guard !groups.isEmpty else { return }

        let arrangedCenters = Self.buildNonOverlappingCenters(for: groups, sizeHintByID: groupBaseSizeHints)
        mutateLayout { layout in
            layout.groups = groups.map { group in
                let existing = layout.groups.first(where: { $0.id == group.id })
                let defaultPoint = arrangedCenters[group.id] ?? Self.defaultGroupPosition(kind: group.kind, index: 0)
                return WorkspaceMapGroupLayoutSnapshot(
                    id: group.id,
                    centerX: defaultPoint.x,
                    centerY: defaultPoint.y,
                    isCollapsed: existing?.isCollapsed ?? false
                )
            }
        }
    }

    func placeNewGroupsWithoutOverlap(
        previousGroupIDs: Set<WorkspaceMapEntityID>,
        viewportCenter: CGPoint? = nil
    ) {
        let groups = snapshot.groups
        guard !groups.isEmpty else { return }

        let newGroups = groups.filter { !previousGroupIDs.contains($0.id) }
        guard !newGroups.isEmpty else { return }

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let activeIDs = Set(groups.map(\.id))

        mutateLayout { layout in
            layout.groups.removeAll { !activeIDs.contains($0.id) }

            var occupiedFrames: [CGRect] = []
            for groupLayout in layout.groups where previousGroupIDs.contains(groupLayout.id) {
                guard let group = groupsByID[groupLayout.id] else { continue }
                let size = Self.groupBaseSize(for: group, sizeHintByID: groupBaseSizeHints)
                occupiedFrames.append(
                    Self.collisionFrame(
                        center: CGPoint(x: groupLayout.centerX, y: groupLayout.centerY),
                        size: size
                    )
                )
            }

            for group in newGroups {
                if !layout.groups.contains(where: { $0.id == group.id }) {
                    let fallbackCenter = viewportCenter ?? Self.defaultGroupPosition(kind: group.kind, index: layout.groups.count)
                    layout.groups.append(
                        WorkspaceMapGroupLayoutSnapshot(
                            id: group.id,
                            centerX: fallbackCenter.x,
                            centerY: fallbackCenter.y,
                            isCollapsed: false
                        )
                    )
                }

                guard let index = layout.groups.firstIndex(where: { $0.id == group.id }) else { continue }
                let size = Self.groupBaseSize(for: group, sizeHintByID: groupBaseSizeHints)
                let candidatePreferredCenter = CGPoint(
                    x: viewportCenter?.x ?? CGFloat(layout.groups[index].centerX),
                    y: viewportCenter?.y ?? CGFloat(layout.groups[index].centerY)
                )
                let resolvedCenter = Self.resolveNonOverlappingCenter(
                    preferredCenter: candidatePreferredCenter,
                    size: size,
                    occupiedFrames: occupiedFrames
                )
                layout.groups[index].centerX = resolvedCenter.x
                layout.groups[index].centerY = resolvedCenter.y
                occupiedFrames.append(Self.collisionFrame(center: resolvedCenter, size: size))
            }
        }
    }

    private func reconcileLayout(with groups: [WorkspaceMapGroupSnapshot]) {
        let activeIDs = Set(groups.map(\.id))
        if groupBaseSizeHints.keys.contains(where: { !activeIDs.contains($0) }) {
            groupBaseSizeHints = groupBaseSizeHints.filter { activeIDs.contains($0.key) }
        }

        mutateLayout(persist: false) { layout in
            let oldByID = Dictionary(uniqueKeysWithValues: layout.groups.map { ($0.id, $0) })
            var terminalIndex = groups.reduce(into: 0) { partial, group in
                if group.kind == .terminal, oldByID[group.id] != nil {
                    partial += 1
                }
            }
            var browserIndex = groups.reduce(into: 0) { partial, group in
                if group.kind == .browser, oldByID[group.id] != nil {
                    partial += 1
                }
            }
            var occupiedFrames: [CGRect] = []
            let merged: [WorkspaceMapGroupLayoutSnapshot] = groups.map { group in
                if let existing = oldByID[group.id] {
                    let existingCenter = CGPoint(x: existing.centerX, y: existing.centerY)
                    let existingSize = Self.groupBaseSize(for: group, sizeHintByID: groupBaseSizeHints)
                    occupiedFrames.append(Self.collisionFrame(center: existingCenter, size: existingSize))
                    return existing
                }

                let index = group.kind == .terminal ? terminalIndex : browserIndex
                if group.kind == .terminal {
                    terminalIndex += 1
                } else {
                    browserIndex += 1
                }

                let defaultPoint = Self.defaultGroupPosition(kind: group.kind, index: index)
                let baseSize = Self.groupBaseSize(for: group, sizeHintByID: groupBaseSizeHints)
                let resolvedPoint = Self.resolveNonOverlappingCenter(
                    preferredCenter: defaultPoint,
                    size: baseSize,
                    occupiedFrames: occupiedFrames
                )
                occupiedFrames.append(Self.collisionFrame(center: resolvedPoint, size: baseSize))
                return WorkspaceMapGroupLayoutSnapshot(
                    id: group.id,
                    centerX: resolvedPoint.x,
                    centerY: resolvedPoint.y,
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

    private static func buildNonOverlappingCenters(
        for groups: [WorkspaceMapGroupSnapshot],
        sizeHintByID: [WorkspaceMapEntityID: CGSize]
    ) -> [WorkspaceMapEntityID: CGPoint] {
        var centers: [WorkspaceMapEntityID: CGPoint] = [:]
        let terminalGroups = groups.filter { $0.kind == .terminal }
        let browserGroups = groups.filter { $0.kind == .browser }

        var nextStartX: CGFloat = 120
        nextStartX = placeGroupsInColumns(
            terminalGroups,
            startX: nextStartX,
            sizeHintByID: sizeHintByID,
            into: &centers
        )

        if !terminalGroups.isEmpty, !browserGroups.isEmpty {
            nextStartX += 260
        }

        _ = placeGroupsInColumns(
            browserGroups,
            startX: nextStartX,
            sizeHintByID: sizeHintByID,
            into: &centers
        )

        return centers
    }

    private static func placeGroupsInColumns(
        _ groups: [WorkspaceMapGroupSnapshot],
        startX: CGFloat,
        sizeHintByID: [WorkspaceMapEntityID: CGSize],
        into centers: inout [WorkspaceMapEntityID: CGPoint]
    ) -> CGFloat {
        let startY: CGFloat = 96
        let verticalGap: CGFloat = 120
        let horizontalGap: CGFloat = 160
        let maxColumnHeight: CGFloat = 2400

        var cursorX = startX
        var cursorY = startY
        var currentColumnWidth: CGFloat = 0
        var rightmostEdge: CGFloat = startX

        for group in groups {
            let size = groupBaseSize(for: group, sizeHintByID: sizeHintByID)

            if cursorY > startY, cursorY + size.height > maxColumnHeight {
                cursorX += currentColumnWidth + horizontalGap
                cursorY = startY
                currentColumnWidth = 0
            }

            let center = CGPoint(
                x: cursorX + size.width / 2,
                y: cursorY + size.height / 2
            )
            centers[group.id] = center

            cursorY += size.height + verticalGap
            currentColumnWidth = max(currentColumnWidth, size.width)
            rightmostEdge = max(rightmostEdge, center.x + size.width / 2)
        }

        return rightmostEdge + horizontalGap
    }

    private static func groupBaseSize(
        for group: WorkspaceMapGroupSnapshot,
        sizeHintByID: [WorkspaceMapEntityID: CGSize]
    ) -> CGSize {
        if let hint = sizeHintByID[group.id] {
            return CGSize(
                width: max(hint.width, 520),
                height: max(hint.height, 320)
            )
        }
        return groupBaseSize(for: group.kind)
    }

    private static func groupBaseSize(for kind: WorkspaceMapGroupKind) -> CGSize {
        switch kind {
        case .terminal:
            return CGSize(width: 880, height: 560)
        case .browser:
            return CGSize(width: 980, height: 680)
        }
    }

    private static func collisionFrame(center: CGPoint, size: CGSize) -> CGRect {
        let gap: CGFloat = 80
        return CGRect(
            x: center.x - size.width / 2 - gap / 2,
            y: center.y - size.height / 2 - gap / 2,
            width: size.width + gap,
            height: size.height + gap
        )
    }

    private static func resolveNonOverlappingCenter(
        preferredCenter: CGPoint,
        size: CGSize,
        occupiedFrames: [CGRect]
    ) -> CGPoint {
        let stepX = max(size.width * 0.55, 360)
        let stepY = max(size.height * 0.55, 280)

        func isAvailable(_ center: CGPoint) -> Bool {
            let frame = collisionFrame(center: center, size: size)
            return occupiedFrames.allSatisfy { !$0.intersects(frame) }
        }

        if isAvailable(preferredCenter) {
            return preferredCenter
        }

        for ring in 1...24 {
            for dx in -ring...ring {
                for dy in -ring...ring {
                    if abs(dx) != ring && abs(dy) != ring {
                        continue
                    }
                    let candidate = CGPoint(
                        x: preferredCenter.x + CGFloat(dx) * stepX,
                        y: preferredCenter.y + CGFloat(dy) * stepY
                    )
                    if isAvailable(candidate) {
                        return candidate
                    }
                }
            }
        }

        var fallback = preferredCenter
        while !isAvailable(fallback) {
            fallback.x += stepX
            fallback.y += stepY * 0.3
        }
        return fallback
    }

    private static func defaultGroupPosition(kind: WorkspaceMapGroupKind, index: Int) -> CGPoint {
        let columns = 2
        let col = index % columns
        let row = index / columns
        let originX = kind == .terminal ? 560.0 : 2920.0
        let columnStride = kind == .terminal ? 1060.0 : 1160.0
        let rowStride = kind == .terminal ? 700.0 : 820.0
        let x = originX + Double(col) * columnStride
        let y = 380.0 + Double(row) * rowStride
        return CGPoint(x: x, y: y)
    }
}

struct WorkspaceMapView: View {
    @ObservedObject var model: WorkspaceMapViewModel
    let contentProvider: WorkspaceMapLiveCanvasContentProvider

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WorkspaceMapLiveCanvasView(model: model, contentProvider: contentProvider)
            if model.snapshot.groups.isEmpty {
                Text(AppLocalization.localizedText("No top-level tabs available."))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    model.scheduleRefresh()
                } label: {
                    Label(AppLocalization.localizedText("Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(AppLocalization.localizedText("Refresh Map"))

                Button {
                    model.autoLayoutGroups()
                } label: {
                    Label(AppLocalization.localizedText("Arrange"), systemImage: "square.grid.3x2")
                }
                .buttonStyle(.bordered)
                .help(AppLocalization.localizedText("Arrange Groups"))
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .padding(12)
        }
        .onAppear {
            model.scheduleRefresh()
        }
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

final class WorkspaceMapController: NSWindowController, NSWindowDelegate, TopLevelTabController {
    private struct PendingNewGroupPlacement {
        let previousGroupIDs: Set<WorkspaceMapEntityID>
        var remainingRefreshes: Int
    }

    private static let pendingPlacementRefreshBudget = 30

    static var all: [WorkspaceMapController] {
        NSApplication.shared.windows.compactMap { $0.windowController as? WorkspaceMapController }
    }

    private let ghostty: Ghostty.App
    private let viewModel = WorkspaceMapViewModel()
    private let liveCanvasContentProvider: WorkspaceMapLiveCanvasContentProvider = WorkspaceMapRuntimeLiveCanvasContentProvider()
    private var windowLifecycleCancellables: Set<AnyCancellable> = []
    private var windowContentConfigured = false
    private var pendingNewGroupPlacements: [PendingNewGroupPlacement] = []

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
        viewModel.setCanvasWindowKeyState(window?.isKeyWindow ?? true)
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

    @IBAction func newTab(_ sender: Any?) {
        _ = createTerminalTabSilently()
    }

    override func newWindowForTab(_ sender: Any?) {
        _ = createTerminalTabSilently()
    }

    @discardableResult
    func createTerminalTabSilently() -> TerminalController? {
        guard let mapWindow = window else { return nil }
        let previousGroupIDs = Set(viewModel.snapshot.groups.map(\.id))
        enqueuePendingNewGroupPlacement(previousGroupIDs: previousGroupIDs)

        let preferredTerminalParent = mapWindow.tabGroup?.windows.first {
            guard $0 !== mapWindow else { return false }
            return $0.windowController is TerminalController
        }

        let createdController: TerminalController
        if let preferredTerminalParent,
           let controller = TerminalController.newTab(ghostty, from: preferredTerminalParent, withBaseConfig: nil) {
            createdController = controller
        } else {
            createdController = TerminalController.newWindow(
                ghostty,
                withBaseConfig: nil,
                withParent: mapWindow
            )
        }

        DispatchQueue.main.async { [weak self, weak mapWindow, weak createdController] in
            guard let self, let mapWindow else { return }

            if let createdWindow = createdController?.window,
               createdWindow !== mapWindow,
               createdWindow.tabbingMode != .disallowed,
               !mapWindow.styleMask.contains(.fullScreen) {
                let isAlreadyInMapTabGroup = mapWindow.tabGroup?.windows.contains(where: { $0 === createdWindow }) ?? false
                if !isAlreadyInMapTabGroup {
                    createdWindow.tabGroup?.removeWindow(createdWindow)
                    mapWindow.addTabbedWindowSafely(createdWindow, ordered: .above)
                }
            }

            self.showWindow(nil)
            mapWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.viewModel.scheduleRefresh()
            self.processPendingNewGroupPlacementsIfNeeded()
        }

        return createdController
    }

    private func enqueuePendingNewGroupPlacement(previousGroupIDs: Set<WorkspaceMapEntityID>) {
        guard !pendingNewGroupPlacements.contains(where: { $0.previousGroupIDs == previousGroupIDs }) else {
            return
        }
        pendingNewGroupPlacements.append(
            PendingNewGroupPlacement(
                previousGroupIDs: previousGroupIDs,
                remainingRefreshes: Self.pendingPlacementRefreshBudget
            )
        )
    }

    private func processPendingNewGroupPlacementsIfNeeded() {
        guard !pendingNewGroupPlacements.isEmpty else { return }
        guard let mapWindow = window else {
            pendingNewGroupPlacements.removeAll()
            return
        }

        let activeGroupIDs = Set(viewModel.snapshot.groups.map(\.id))
        var retained: [PendingNewGroupPlacement] = []

        for var pending in pendingNewGroupPlacements {
            let newGroupIDs = activeGroupIDs.subtracting(pending.previousGroupIDs)
            if newGroupIDs.isEmpty {
                pending.remainingRefreshes -= 1
                if pending.remainingRefreshes > 0 {
                    retained.append(pending)
                }
                continue
            }

            placeAndCenterNewGroups(
                previousGroupIDs: pending.previousGroupIDs,
                in: mapWindow
            )
        }

        pendingNewGroupPlacements = retained
    }

    private func placeAndCenterNewGroups(
        previousGroupIDs: Set<WorkspaceMapEntityID>,
        in mapWindow: NSWindow
    ) {
        let viewportCenter = currentViewportLogicalCenter(in: mapWindow)
        viewModel.placeNewGroupsWithoutOverlap(
            previousGroupIDs: previousGroupIDs,
            viewportCenter: viewportCenter
        )

        let newGroupID = viewModel.snapshot.groups
            .map(\.id)
            .last(where: { !previousGroupIDs.contains($0) })
        guard let newGroupID else { return }
        centerViewport(on: newGroupID, in: mapWindow)
    }

    private func currentViewportLogicalCenter(in mapWindow: NSWindow) -> CGPoint? {
        guard let contentBounds = mapWindow.contentView?.bounds,
              contentBounds.width > 1,
              contentBounds.height > 1 else {
            return nil
        }
        let zoom = max(viewModel.zoomScale, 0.001)
        let offset = viewModel.viewportOffset
        return CGPoint(
            x: (contentBounds.midX - offset.width) / zoom,
            y: (contentBounds.midY - offset.height) / zoom
        )
    }

    private func centerViewport(on groupID: WorkspaceMapEntityID, in mapWindow: NSWindow) {
        guard let contentBounds = mapWindow.contentView?.bounds,
              contentBounds.width > 1,
              contentBounds.height > 1 else {
            return
        }
        let zoom = max(viewModel.zoomScale, 0.001)
        let center = viewModel.groupPosition(for: groupID)
        viewModel.setViewportOffset(
            CGSize(
                width: contentBounds.midX - center.x * zoom,
                height: contentBounds.midY - center.y * zoom
            )
        )
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setCanvasPresentationActive(true)
        viewModel.setCanvasWindowKeyState(true)
        viewModel.scheduleRefresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setCanvasWindowKeyState(false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        viewModel.setCanvasPresentationActive(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        viewModel.setCanvasPresentationActive(true)
        viewModel.scheduleRefresh()
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

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.setCanvasPresentationActive(false)
                self?.viewModel.setCanvasWindowKeyState(false)
                self?.viewModel.scheduleRefresh()
                self?.pendingNewGroupPlacements.removeAll()
            }
            .store(in: &windowLifecycleCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification, object: nil)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.scheduleRefresh()
            }
            .store(in: &windowLifecycleCancellables)

        viewModel.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.processPendingNewGroupPlacementsIfNeeded()
            }
            .store(in: &windowLifecycleCancellables)
    }
}
