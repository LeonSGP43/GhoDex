import AppKit
import SwiftUI

struct WorkspaceMapLiveCanvasView: NSViewRepresentable {
    @ObservedObject var model: WorkspaceMapViewModel
    let contentProvider: WorkspaceMapLiveCanvasContentProvider

    func makeNSView(context: Context) -> WorkspaceMapCanvasHostView {
        let view = WorkspaceMapCanvasHostView(model: model, contentProvider: contentProvider)
        view.update(snapshot: model.snapshot, layout: model.layout, isPresentationActive: model.isCanvasPresentationActive)
        return view
    }

    func updateNSView(_ nsView: WorkspaceMapCanvasHostView, context: Context) {
        nsView.model = model
        nsView.contentProvider = contentProvider
        nsView.update(snapshot: model.snapshot, layout: model.layout, isPresentationActive: model.isCanvasPresentationActive)
    }

    static func dismantleNSView(_ nsView: WorkspaceMapCanvasHostView, coordinator: ()) {
        nsView.restoreBorrowedViews()
    }
}

@MainActor
final class WorkspaceMapCanvasHostView: NSView {
    weak var model: WorkspaceMapViewModel?
    weak var contentProvider: WorkspaceMapLiveCanvasContentProvider?

    private var snapshot = WorkspaceMapSnapshot(groups: [])
    private var layoutSnapshot = WorkspaceMapLayoutSnapshot(groups: [])
    private var isPresentationActive = false
    private var nodeViews: [WorkspaceMapEntityID: WorkspaceMapLiveNodeView] = [:]
    private var borrowedViews: [WorkspaceMapEntityID: WorkspaceMapLiveCanvasLease] = [:]
    private var cachedBaseSizes: [WorkspaceMapEntityID: CGSize] = [:]
    private var canvasPanStartViewportOffset: CGSize?
    private var canvasPanStartPoint: CGPoint?
    private var lastSnapshotSignature: Int?
    private var lastAutoViewportSignature: Int?
    private var pendingVisibilitySnapshotSignature: Int?
    private var selectedGroupID: WorkspaceMapEntityID?
    private var immersiveGroupID: WorkspaceMapEntityID?
    private var isSpacePanModifierActive = false
    private var isSpacePanDragActive = false
    private var hasPushedOpenHandCursor = false
    private var hasPushedClosedHandCursor = false

    private enum ImmersiveFitMode {
        case bestFit
        case fitHeight
        case fitWidth
        case actualScale
    }

    init(model: WorkspaceMapViewModel, contentProvider: WorkspaceMapLiveCanvasContentProvider?) {
        self.model = model
        self.contentProvider = contentProvider
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WorkspaceMapCanvasHostView")
    }

    func update(
        snapshot: WorkspaceMapSnapshot,
        layout: WorkspaceMapLayoutSnapshot,
        isPresentationActive: Bool
    ) {
        let snapshotSignature = Self.snapshotSignature(snapshot.groups)
        let snapshotChanged = snapshotSignature != lastSnapshotSignature

        self.snapshot = snapshot
        self.layoutSnapshot = layout
        self.isPresentationActive = isPresentationActive
        syncNodes()

        if snapshotChanged {
            pendingVisibilitySnapshotSignature = snapshotSignature
            if ensureVisibleNodesIfNeeded() {
                lastSnapshotSignature = snapshotSignature
                pendingVisibilitySnapshotSignature = nil
            }
        }

        if isPresentationActive {
            syncBorrowedViews()
        } else {
            restoreBorrowedViews()
        }
    }

    func restoreBorrowedViews() {
        for lease in borrowedViews.values {
            if let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
                mirror.onUserInteraction = nil
            }
            lease.release()
        }
        borrowedViews.removeAll()
        for nodeView in nodeViews.values {
            nodeView.clearBorrowedContent()
        }
    }

    override func layout() {
        super.layout()
        syncNodeFrames()

        if let pendingSignature = pendingVisibilitySnapshotSignature,
           pendingSignature != lastSnapshotSignature,
           ensureVisibleNodesIfNeeded() {
            lastSnapshotSignature = pendingSignature
            pendingVisibilitySnapshotSignature = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let path = NSBezierPath()
        let step: CGFloat = 52
        let offset = layoutSnapshot.viewport
        let zoom = max(CGFloat(offset.zoom), 0.45)
        let startX = CGFloat(offset.offsetX).truncatingRemainder(dividingBy: step * zoom)
        let startY = CGFloat(offset.offsetY).truncatingRemainder(dividingBy: step * zoom)
        NSColor.secondaryLabelColor.withAlphaComponent(0.08).setStroke()

        var x = startX
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))
            x += step * zoom
        }

        var y = startY
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: bounds.width, y: y))
            y += step * zoom
        }

        path.lineWidth = 1
        path.stroke()
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            clearHandCursorState()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if handleCanvasKeyShortcut(event) {
            return
        }
        if WorkspaceMapCanvasInputPolicy.isSpaceKey(event) {
            activateSpacePanMode()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCanvasKeyEquivalent(event) {
            return true
        }
        if forwardSelectedTerminalKeyEquivalent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if WorkspaceMapCanvasInputPolicy.isSpaceKey(event) {
            deactivateSpacePanMode()
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        deactivateSpacePanMode()
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let selected = topmostGroupID(at: point) {
            selectedGroupID = selected
        }
        if isSpacePanModifierActive {
            window?.makeFirstResponder(self)
            canvasPanStartPoint = point
            canvasPanStartViewportOffset = model?.viewportOffset ?? .zero
            isSpacePanDragActive = true
            updateHandCursorForDragState()
            return
        }
        guard hitTest(point) === self else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        canvasPanStartPoint = point
        canvasPanStartViewportOffset = model?.viewportOffset ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let startPoint = canvasPanStartPoint, let startOffset = canvasPanStartViewportOffset else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        model.setViewportOffset(
            CGSize(
                width: startOffset.width + (point.x - startPoint.x),
                height: startOffset.height + (point.y - startPoint.y)
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        canvasPanStartPoint = nil
        canvasPanStartViewportOffset = nil
        if isSpacePanDragActive {
            isSpacePanDragActive = false
            updateHandCursorForDragState()
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model else {
            super.scrollWheel(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard hitTest(point) === self else {
            super.scrollWheel(with: event)
            return
        }

        switch WorkspaceMapCanvasInputPolicy.wheelInteractionMode(
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            modifierFlags: event.modifierFlags
        ) {
        case .pan:
            let current = model.viewportOffset
            model.setViewportOffset(
                CGSize(
                    width: current.width - event.scrollingDeltaX,
                    height: current.height - event.scrollingDeltaY
                )
            )
        case .zoom:
            let currentZoom = model.zoomScale
            let primaryDelta: CGFloat = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? event.scrollingDeltaY
                : -event.scrollingDeltaX
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.04
            let zoomDelta = max(min(-primaryDelta * sensitivity, 0.35), -0.35)
            let proposedZoom = max(min(currentZoom + zoomDelta, 2.2), 0.45)
            guard abs(proposedZoom - currentZoom) > 0.0001 else { return }

            let logicalX = (point.x - model.viewportOffset.width) / currentZoom
            let logicalY = (point.y - model.viewportOffset.height) / currentZoom
            model.setZoom(proposedZoom)
            model.setViewportOffset(
                CGSize(
                    width: point.x - logicalX * proposedZoom,
                    height: point.y - logicalY * proposedZoom
                )
            )
        }
    }

    fileprivate func beginDraggingNode(_ groupID: WorkspaceMapEntityID, with event: NSEvent) {
        guard let model else { return }
        selectedGroupID = groupID
        let startWindowPoint = event.locationInWindow
        let startLogicalPoint = model.groupPosition(for: groupID)

        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .greatestFiniteMagnitude, mode: .eventTracking) { [weak self] trackedEvent, stop in
            guard self != nil else {
                stop.pointee = true
                return
            }

            guard let trackedEvent else {
                stop.pointee = true
                return
            }

            switch trackedEvent.type {
            case .leftMouseDragged:
                let currentWindowPoint = trackedEvent.locationInWindow
                let deltaX = (currentWindowPoint.x - startWindowPoint.x) / model.zoomScale
                let deltaY = (currentWindowPoint.y - startWindowPoint.y) / model.zoomScale
                model.setGroupPosition(
                    groupID,
                    point: CGPoint(x: startLogicalPoint.x + deltaX, y: startLogicalPoint.y + deltaY)
                )
            default:
                stop.pointee = true
            }
        }
    }

    private func activateSpacePanMode() {
        guard !isSpacePanModifierActive else { return }
        isSpacePanModifierActive = true
        window?.makeFirstResponder(self)
        updateHandCursorForDragState()
    }

    private func deactivateSpacePanMode() {
        guard isSpacePanModifierActive || isSpacePanDragActive else { return }
        isSpacePanModifierActive = false
        isSpacePanDragActive = false
        canvasPanStartPoint = nil
        canvasPanStartViewportOffset = nil
        updateHandCursorForDragState()
    }

    private func updateHandCursorForDragState() {
        if hasPushedOpenHandCursor {
            NSCursor.pop()
            hasPushedOpenHandCursor = false
        }
        if hasPushedClosedHandCursor {
            NSCursor.pop()
            hasPushedClosedHandCursor = false
        }

        guard isSpacePanModifierActive else { return }
        if isSpacePanDragActive {
            NSCursor.closedHand.push()
            hasPushedClosedHandCursor = true
        } else {
            NSCursor.openHand.push()
            hasPushedOpenHandCursor = true
        }
    }

    private func clearHandCursorState() {
        if hasPushedOpenHandCursor {
            NSCursor.pop()
            hasPushedOpenHandCursor = false
        }
        if hasPushedClosedHandCursor {
            NSCursor.pop()
            hasPushedClosedHandCursor = false
        }
        isSpacePanModifierActive = false
        isSpacePanDragActive = false
    }

    private func handleCanvasKeyShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 53,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            if immersiveGroupID != nil {
                immersiveGroupID = nil
                syncNodeFrames()
                return true
            }
            return false
        }

        return handleDirectionalFocusShortcut(event)
    }

    private func handleCanvasKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return handleDirectionalFocusShortcut(event)
    }

    private func handleDirectionalFocusShortcut(_ event: NSEvent) -> Bool {
        if let direction = WorkspaceMapCanvasInputPolicy.focusShortcutDirection(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) {
            moveFocus(to: direction)
            return true
        }

        return false
    }

    private func moveFocus(to direction: WorkspaceMapCanvasInputPolicy.FocusShortcutDirection) {
        guard let model,
              let currentID = preferredFocusGroupID() else {
            return
        }
        let currentPoint = model.groupPosition(for: currentID)
        var bestCandidate: (id: WorkspaceMapEntityID, score: CGFloat)?

        for candidate in snapshot.groups where candidate.id != currentID {
            let candidatePoint = model.groupPosition(for: candidate.id)
            let deltaX = candidatePoint.x - currentPoint.x
            let deltaY = candidatePoint.y - currentPoint.y

            guard let score = directionalFocusScore(
                deltaX: deltaX,
                deltaY: deltaY,
                direction: direction
            ) else {
                continue
            }

            if let currentBest = bestCandidate {
                if score < currentBest.score {
                    bestCandidate = (candidate.id, score)
                }
            } else {
                bestCandidate = (candidate.id, score)
            }
        }

        guard let targetID = bestCandidate?.id else { return }
        selectedGroupID = targetID

        if immersiveGroupID != nil {
            immersiveGroupID = targetID
            syncNodeFrames()
        } else {
            centerViewport(on: targetID)
        }

        focusMirrorIfAvailable(for: targetID)
    }

    private func directionalFocusScore(
        deltaX: CGFloat,
        deltaY: CGFloat,
        direction: WorkspaceMapCanvasInputPolicy.FocusShortcutDirection
    ) -> CGFloat? {
        let minPrimaryDistance: CGFloat = 8
        let maxAlignmentRatio: CGFloat = 1.8

        let primary: CGFloat
        let lateral: CGFloat
        switch direction {
        case .up:
            primary = deltaY
            lateral = abs(deltaX)
        case .down:
            primary = -deltaY
            lateral = abs(deltaX)
        case .left:
            primary = -deltaX
            lateral = abs(deltaY)
        case .right:
            primary = deltaX
            lateral = abs(deltaY)
        }

        guard primary > minPrimaryDistance else { return nil }
        let alignmentRatio = lateral / max(primary, 0.001)
        guard alignmentRatio <= maxAlignmentRatio else { return nil }

        let distance = hypot(deltaX, deltaY)
        return alignmentRatio * 800 + distance
    }

    private func centerViewport(on groupID: WorkspaceMapEntityID) {
        guard let model else { return }
        let zoom = model.zoomScale
        let center = model.groupPosition(for: groupID)
        model.setViewportOffset(
            CGSize(
                width: bounds.midX - center.x * zoom,
                height: bounds.midY - center.y * zoom
            )
        )
    }

    private func focusMirrorIfAvailable(for groupID: WorkspaceMapEntityID) {
        guard let lease = borrowedViews[groupID],
              let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView else {
            return
        }
        _ = window?.makeFirstResponder(mirror)
    }

    private func focusPreferredGroup(mode: ImmersiveFitMode) {
        guard let targetID = preferredFocusGroupID() else { return }
        selectedGroupID = targetID
        focusGroup(targetID, mode: mode)
    }

    private func preferredFocusGroupID() -> WorkspaceMapEntityID? {
        if let selectedGroupID,
           snapshot.groups.contains(where: { $0.id == selectedGroupID }) {
            return selectedGroupID
        }

        if let focused = snapshot.groups.first(where: \.isFocused)?.id {
            return focused
        }

        return snapshot.groups.first?.id
    }

    private func focusGroup(_ groupID: WorkspaceMapEntityID, mode: ImmersiveFitMode) {
        guard let model,
              let group = snapshot.groups.first(where: { $0.id == groupID }),
              bounds.width > 80,
              bounds.height > 80 else {
            return
        }

        let baseSize = resolvedBaseSize(for: groupID, groupKind: group.kind)
        let available = bounds.insetBy(dx: 44, dy: 56)
        guard available.width > 40, available.height > 40 else { return }

        let fitWidthZoom = available.width / baseSize.width
        let fitHeightZoom = available.height / baseSize.height
        let desiredZoom: CGFloat
        switch mode {
        case .bestFit:
            desiredZoom = min(fitWidthZoom, fitHeightZoom)
        case .fitHeight:
            desiredZoom = fitHeightZoom
        case .fitWidth:
            desiredZoom = fitWidthZoom
        case .actualScale:
            desiredZoom = 1.0
        }
        let clampedZoom = max(min(desiredZoom, 2.2), 0.45)
        let center = model.groupPosition(for: groupID)

        model.setZoom(clampedZoom)
        model.setViewportOffset(
            CGSize(
                width: bounds.midX - center.x * clampedZoom,
                height: bounds.midY - center.y * clampedZoom
            )
        )
    }

    private func forwardSelectedTerminalKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        guard key == "=" || key == "-" || key == "0" else { return false }

        if let targetID = preferredFocusGroupID(),
           let lease = borrowedViews[targetID],
           let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
            selectedGroupID = targetID
            _ = window?.makeFirstResponder(mirror)
            if mirror.performKeyEquivalent(with: event) {
                return true
            }
            mirror.keyDown(with: event)
            return true
        }

        if let currentResponder = window?.firstResponder as? WorkspaceMapRuntimeInteractiveMirrorView {
            if currentResponder.performKeyEquivalent(with: event) {
                return true
            }
            currentResponder.keyDown(with: event)
            return true
        }

        return false
    }

    private func topmostGroupID(at point: CGPoint) -> WorkspaceMapEntityID? {
        for view in subviews.reversed() {
            guard let node = view as? WorkspaceMapLiveNodeView else { continue }
            guard !node.isHidden else { continue }
            if node.frame.contains(point) {
                return node.groupID
            }
        }
        return nil
    }

    private func syncNodes() {
        let groupsByID = Dictionary(uniqueKeysWithValues: snapshot.groups.map { ($0.id, $0) })

        for (id, nodeView) in nodeViews where groupsByID[id] == nil {
            nodeView.removeFromSuperview()
            nodeViews.removeValue(forKey: id)
            if let lease = borrowedViews.removeValue(forKey: id) {
                if let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
                    mirror.onUserInteraction = nil
                }
                lease.release()
            }
            cachedBaseSizes.removeValue(forKey: id)
            if selectedGroupID == id {
                selectedGroupID = nil
            }
            if immersiveGroupID == id {
                immersiveGroupID = nil
            }
        }

        for group in snapshot.groups {
            let nodeView = nodeViews[group.id] ?? makeNodeView(for: group)
            nodeViews[group.id] = nodeView
            if nodeView.superview !== self {
                addSubview(nodeView)
            }
            nodeView.update(group: group)
        }

        syncNodeFrames()
        needsDisplay = true
    }

    private func ensureVisibleNodesIfNeeded() -> Bool {
        guard let model else { return false }
        guard !snapshot.groups.isEmpty else {
            lastAutoViewportSignature = nil
            return true
        }
        guard bounds.width > 0, bounds.height > 0 else { return false }

        let visibleBounds = bounds.insetBy(dx: 36, dy: 36)
        let hasVisibleNode = snapshot.groups.contains { group in
            guard let nodeView = nodeViews[group.id] else { return false }
            return nodeView.frame.intersects(visibleBounds)
        }
        if hasVisibleNode {
            lastAutoViewportSignature = nil
            return true
        }

        let visibilitySignature = makeVisibilitySignature(
            groupIDs: snapshot.groups.map(\.id),
            zoom: model.zoomScale,
            boundsSize: bounds.size
        )
        guard lastAutoViewportSignature != visibilitySignature else { return true }

        let logicalCenters = snapshot.groups.map { model.groupPosition(for: $0.id) }
        guard !logicalCenters.isEmpty else { return true }
        let centroidX = logicalCenters.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(logicalCenters.count)
        let centroidY = logicalCenters.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(logicalCenters.count)
        let zoom = max(model.zoomScale, 0.001)

        model.setViewportOffset(
            CGSize(
                width: bounds.midX - centroidX * zoom,
                height: bounds.midY - centroidY * zoom
            )
        )
        lastAutoViewportSignature = visibilitySignature
        return true
    }

    private func makeNodeView(for group: WorkspaceMapGroupSnapshot) -> WorkspaceMapLiveNodeView {
        WorkspaceMapLiveNodeView(
            group: group,
            onDrag: { [weak self] groupID, event in
                self?.selectedGroupID = groupID
                self?.beginDraggingNode(groupID, with: event)
            },
            onHeaderDoubleClick: { [weak self] groupID in
                guard let self else { return }
                self.selectedGroupID = groupID
                self.toggleImmersiveMode(for: groupID)
            }
        )
    }

    private func syncBorrowedViews() {
        let activeIDs = Set(snapshot.groups.map(\.id))
        var sizeHintChanged = false
        for (id, lease) in borrowedViews where !activeIDs.contains(id) {
            if let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
                mirror.onUserInteraction = nil
            }
            lease.release()
            borrowedViews.removeValue(forKey: id)
        }

        for group in snapshot.groups {
            guard let nodeView = nodeViews[group.id] else { continue }
            if let lease = borrowedViews[group.id] {
                if let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
                    mirror.onUserInteraction = { [weak self] in
                        self?.selectedGroupID = group.id
                    }
                    let measuredSize = mirror.sourceContentSize ?? lease.baseSize
                    if recordBaseSizeHint(measuredSize, for: group.id) {
                        sizeHintChanged = true
                    }
                } else if recordBaseSizeHint(lease.baseSize, for: group.id) {
                    sizeHintChanged = true
                }
                nodeView.attachBorrowedContentView(lease.borrowedView)
                continue
            }

            guard let contentProvider else {
                nodeView.setUnavailableMessage("Live content provider unavailable")
                continue
            }

            switch contentProvider.acquireLease(for: group) {
            case .lease(let lease):
                borrowedViews[group.id] = lease
                if recordBaseSizeHint(lease.baseSize, for: group.id) {
                    sizeHintChanged = true
                }
                if let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView {
                    mirror.onUserInteraction = { [weak self] in
                        self?.selectedGroupID = group.id
                    }
                    let measuredSize = mirror.sourceContentSize ?? lease.baseSize
                    if recordBaseSizeHint(measuredSize, for: group.id) {
                        sizeHintChanged = true
                    }
                }
                nodeView.attachBorrowedContentView(lease.borrowedView)
            case .unavailable(let message):
                nodeView.setUnavailableMessage(message)
            }
        }

        if sizeHintChanged {
            syncNodeFrames()
        }
    }

    private func syncNodeFrames() {
        guard let model else { return }
        if let immersiveGroupID {
            guard snapshot.groups.contains(where: { $0.id == immersiveGroupID }),
                  let immersiveNodeView = nodeViews[immersiveGroupID] else {
                self.immersiveGroupID = nil
                syncNodeFrames()
                return
            }
            for (id, nodeView) in nodeViews {
                if id == immersiveGroupID {
                    nodeView.isHidden = false
                } else {
                    nodeView.isHidden = true
                }
            }
            immersiveNodeView.frame = bounds
            immersiveNodeView.zoomScale = 1
            immersiveNodeView.superview?.addSubview(immersiveNodeView, positioned: .above, relativeTo: nil)
            return
        }

        for nodeView in nodeViews.values {
            nodeView.isHidden = false
        }

        let layoutByID = Dictionary(uniqueKeysWithValues: layoutSnapshot.groups.map { ($0.id, $0) })
        let zoom = model.zoomScale
        let viewport = model.viewportOffset

        for group in snapshot.groups {
            guard let nodeView = nodeViews[group.id] else { continue }
            let baseSize = resolvedBaseSize(for: group.id, groupKind: group.kind)
            let layoutSnapshot = layoutByID[group.id]
            let logicalCenter = layoutSnapshot.map { CGPoint(x: $0.centerX, y: $0.centerY) } ?? model.groupPosition(for: group.id)
            let scaledSize = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
            let origin = CGPoint(
                x: logicalCenter.x * zoom + viewport.width - scaledSize.width / 2,
                y: logicalCenter.y * zoom + viewport.height - scaledSize.height / 2
            )
            nodeView.frame = CGRect(origin: origin, size: scaledSize)
            nodeView.zoomScale = zoom
            if group.isFocused {
                nodeView.superview?.addSubview(nodeView, positioned: .above, relativeTo: nil)
            }
        }
    }

    private func toggleImmersiveMode(for groupID: WorkspaceMapEntityID) {
        if immersiveGroupID == groupID {
            immersiveGroupID = nil
        } else {
            immersiveGroupID = groupID
        }
        syncNodeFrames()
    }

    private func resolvedBaseSize(for groupID: WorkspaceMapEntityID, groupKind: WorkspaceMapGroupKind) -> CGSize {
        if let cached = cachedBaseSizes[groupID] {
            return cached
        }

        switch groupKind {
        case .terminal:
            return CGSize(width: 880, height: 560)
        case .browser:
            return CGSize(width: 980, height: 680)
        }
    }

    @discardableResult
    private func recordBaseSizeHint(_ size: CGSize, for groupID: WorkspaceMapEntityID) -> Bool {
        let headerHeight = WorkspaceMapLiveNodeView.headerHeight
        let normalized = CGSize(
            width: max(size.width, 520),
            height: max(size.height + headerHeight, 320 + headerHeight)
        )
        if let existing = cachedBaseSizes[groupID],
           abs(existing.width - normalized.width) < 0.5,
           abs(existing.height - normalized.height) < 0.5 {
            return false
        }

        cachedBaseSizes[groupID] = normalized
        model?.updateGroupBaseSizeHint(groupID, size: normalized)
        return true
    }

    private func makeVisibilitySignature(
        groupIDs: [WorkspaceMapEntityID],
        zoom: CGFloat,
        boundsSize: CGSize
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(groupIDs.count)
        groupIDs.forEach { hasher.combine($0.rawValue) }
        hasher.combine(Int((zoom * 100).rounded()))
        hasher.combine(Int(boundsSize.width.rounded()))
        hasher.combine(Int(boundsSize.height.rounded()))
        return hasher.finalize()
    }

    private static func snapshotSignature(_ groups: [WorkspaceMapGroupSnapshot]) -> Int {
        var hasher = Hasher()
        hasher.combine(groups.count)
        groups.forEach { group in
            hasher.combine(group.id.rawValue)
            hasher.combine(group.kind.rawValue)
        }
        return hasher.finalize()
    }
}

private final class WorkspaceMapLiveNodeView: NSView {
    static let headerHeight: CGFloat = 24

    private let headerView = WorkspaceMapLiveNodeHeaderView()
    private let bodyView = NSView()
    private let unavailableLabel = NSTextField(labelWithString: "")
    private var currentBorrowedView: NSView?
    fileprivate(set) var groupID: WorkspaceMapEntityID
    var zoomScale: CGFloat = 1 {
        didSet {
            headerView.zoomScale = zoomScale
            needsLayout = true
        }
    }

    init(
        group: WorkspaceMapGroupSnapshot,
        onDrag: @escaping (WorkspaceMapEntityID, NSEvent) -> Void,
        onHeaderDoubleClick: @escaping (WorkspaceMapEntityID) -> Void
    ) {
        self.groupID = group.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        addSubview(bodyView)
        addSubview(headerView)
        headerView.onDrag = { [groupID = group.id] event in
            onDrag(groupID, event)
        }
        headerView.onDoubleClick = { [groupID = group.id] in
            onHeaderDoubleClick(groupID)
        }
        bodyView.wantsLayer = true
        bodyView.layer?.backgroundColor = NSColor.black.cgColor
        unavailableLabel.alignment = .center
        unavailableLabel.textColor = .secondaryLabelColor
        unavailableLabel.stringValue = "Preparing live view..."
        bodyView.addSubview(unavailableLabel)
        update(group: group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WorkspaceMapLiveNodeView")
    }

    override func layout() {
        super.layout()
        let headerHeight = Self.headerHeight
        let bodyHeight = max(bounds.height - headerHeight, 1)
        bodyView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bodyHeight)
        headerView.frame = CGRect(x: 0, y: bodyHeight, width: bounds.width, height: headerHeight)
        currentBorrowedView?.frame = bodyView.bounds
        unavailableLabel.frame = bodyView.bounds.insetBy(dx: 12, dy: 12)
    }

    func update(group: WorkspaceMapGroupSnapshot) {
        groupID = group.id
        headerView.update(title: group.title, isFocused: group.isFocused)
        layer?.borderColor = (group.isFocused ? NSColor.controlAccentColor.withAlphaComponent(0.7) : NSColor.separatorColor.withAlphaComponent(0.3)).cgColor
        layer?.backgroundColor = (group.isFocused ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.controlBackgroundColor.withAlphaComponent(0.96)).cgColor
    }

    func attachBorrowedContentView(_ view: NSView) {
        unavailableLabel.removeFromSuperview()
        if currentBorrowedView === view {
            needsLayout = true
            return
        }
        currentBorrowedView?.removeFromSuperview()
        currentBorrowedView = view
        if view.superview !== bodyView {
            bodyView.addSubview(view)
        }
        view.frame = bodyView.bounds
        view.autoresizingMask = [.width, .height]
        needsLayout = true
    }

    func clearBorrowedContent() {
        currentBorrowedView?.removeFromSuperview()
        currentBorrowedView = nil
    }

    func setUnavailableMessage(_ text: String) {
        clearBorrowedContent()
        unavailableLabel.stringValue = text
        if unavailableLabel.superview !== bodyView {
            bodyView.addSubview(unavailableLabel)
        }
        needsLayout = true
    }
}

private final class WorkspaceMapLiveNodeHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    var onDrag: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    var zoomScale: CGFloat = 1 {
        didSet {
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WorkspaceMapLiveNodeHeaderView")
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 10
        titleLabel.frame = CGRect(x: padding, y: 0, width: max(bounds.width - padding * 2, 40), height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        onDrag?(event)
    }

    func update(title: String, isFocused: Bool) {
        titleLabel.stringValue = title
        titleLabel.textColor = isFocused ? .labelColor : .secondaryLabelColor
        layer?.backgroundColor = (isFocused ? NSColor.controlAccentColor.withAlphaComponent(0.09) : NSColor.underPageBackgroundColor.withAlphaComponent(0.88)).cgColor
    }
}
