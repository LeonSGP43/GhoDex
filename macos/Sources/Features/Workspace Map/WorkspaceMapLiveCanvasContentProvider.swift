import AppKit
import QuartzCore
import GhoDexKit

@MainActor
protocol WorkspaceMapLiveCanvasContentProvider: AnyObject {
    func acquireLease(for group: WorkspaceMapGroupSnapshot) -> WorkspaceMapLiveCanvasLeaseResult
}

enum WorkspaceMapLiveCanvasLeaseResult {
    case lease(WorkspaceMapLiveCanvasLease)
    case unavailable(String)
}

struct WorkspaceMapLiveCanvasLease {
    let borrowedView: NSView
    let baseSize: CGSize
    let release: @MainActor () -> Void
}

struct WorkspaceMapLiveCanvasRenderPathMetrics: Equatable, Sendable {
    let sharedTransportFrameCount: Int
    let bitmapFallbackFrameCount: Int

    var totalFrameCount: Int {
        sharedTransportFrameCount + bitmapFallbackFrameCount
    }

    var sharedTransportHitRate: Double {
        guard totalFrameCount > 0 else { return 0 }
        return Double(sharedTransportFrameCount) / Double(totalFrameCount)
    }
}

@MainActor
enum WorkspaceMapLiveCanvasRenderPathRecorder {
    private static var sharedTransportFrameCount = 0
    private static var bitmapFallbackFrameCount = 0

    static func recordSharedTransportFrame() {
        sharedTransportFrameCount += 1
    }

    static func recordBitmapFallbackFrame() {
        bitmapFallbackFrameCount += 1
    }

    static func snapshot() -> WorkspaceMapLiveCanvasRenderPathMetrics {
        WorkspaceMapLiveCanvasRenderPathMetrics(
            sharedTransportFrameCount: sharedTransportFrameCount,
            bitmapFallbackFrameCount: bitmapFallbackFrameCount
        )
    }

    static func reset() {
        sharedTransportFrameCount = 0
        bitmapFallbackFrameCount = 0
    }
}

@MainActor
final class WorkspaceMapRuntimeLiveCanvasContentProvider: WorkspaceMapLiveCanvasContentProvider {
    typealias SourceViewResolver = @MainActor (WorkspaceMapEntityID) -> NSView?
    typealias MirrorViewFactory = @MainActor (NSView) -> WorkspaceMapRuntimeInteractiveMirrorView

    private let sourceViewResolver: SourceViewResolver
    private let mirrorViewFactory: MirrorViewFactory

    init(
        sourceViewResolver: @escaping SourceViewResolver = { groupID in
            WorkspaceMapRuntimeLiveCanvasContentProvider.defaultSourceView(groupID)
        },
        mirrorViewFactory: @escaping MirrorViewFactory = {
            WorkspaceMapRuntimeInteractiveMirrorView(sourceView: $0)
        }
    ) {
        self.sourceViewResolver = sourceViewResolver
        self.mirrorViewFactory = mirrorViewFactory
    }

    func acquireLease(for group: WorkspaceMapGroupSnapshot) -> WorkspaceMapLiveCanvasLeaseResult {
        guard group.kind == .terminal else {
            return .unavailable("Browser live embedding is blocked by current CEF window ownership.")
        }

        guard let sourceView = sourceViewResolver(group.id) else {
            return .unavailable("Terminal unavailable")
        }

        let mirrorView = mirrorViewFactory(sourceView)

        let lease = WorkspaceMapLiveCanvasLease(
            borrowedView: mirrorView,
            baseSize: CGSize(
                width: max(sourceView.bounds.width, 520),
                height: max(sourceView.bounds.height, 320)
            ),
            release: { [weak mirrorView] in
                mirrorView?.stopMirroring()
            }
        )
        return .lease(lease)
    }

    private static func defaultSourceView(_ groupID: WorkspaceMapEntityID) -> NSView? {
        guard let terminalUUID = groupID.terminalGroupUUID else {
            return nil
        }
        return TerminalController.all.first(where: { $0.workspaceID == terminalUUID })?.window?.contentView
    }
}

@MainActor
final class WorkspaceMapRuntimeInteractiveMirrorView: NSView {
    private static let interactionBoostRefreshInterval: TimeInterval = 1.0 / 60.0
    private static let focusedRefreshInterval: TimeInterval = 1.0 / 45.0
    private static let idleRefreshInterval: TimeInterval = 1.0 / 15.0
    private static let interactionBoostDuration: TimeInterval = 1.0
    private static let interactionBurstDelays: [TimeInterval] = [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0]
    private static let undoSelector = #selector(WorkspaceMapRuntimeInteractiveMirrorView.undo(_:))
    private static let redoSelector = #selector(WorkspaceMapRuntimeInteractiveMirrorView.redo(_:))

    private weak var sourceView: NSView?
    private let imageView = NSImageView(frame: .zero)
    private let sharedSurfaceLayer = CALayer()
    private let sharedSurfaceCandidatesProvider: (@MainActor (NSView) -> [(NSView, CALayer)])?
    private weak var sharedSurfaceRootView: NSView?
    private var sharedSurfaceMirrors: [SharedSurfaceMirror] = []
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 1.0 / 12.0
    private weak var leftDragTargetView: NSView?
    private weak var rightDragTargetView: NSView?
    private weak var otherDragTargetView: NSView?
    private weak var keyboardTargetView: NSView?
    private weak var activeSurfaceView: Ghostty.SurfaceView?
    private weak var forcedFocusedSurfaceView: Ghostty.SurfaceView?
    private var interactionBoostUntil: CFAbsoluteTime = 0
    private var pendingBurstCaptureWorkItems: [DispatchWorkItem] = []
    private var lastInteractionSourcePoint: CGPoint?
    private(set) var isMirroringActive = false

    private struct SharedSurfaceCandidate {
        let view: NSView
        let layer: CALayer
    }

    private final class SharedSurfaceMirror {
        weak var sourceView: NSView?
        weak var sourceLayer: CALayer?
        let mirrorLayer: CALayer

        init(sourceView: NSView, sourceLayer: CALayer) {
            self.sourceView = sourceView
            self.sourceLayer = sourceLayer
            self.mirrorLayer = CALayer()
            self.mirrorLayer.contentsGravity = .resize
            self.mirrorLayer.minificationFilter = .nearest
            self.mirrorLayer.magnificationFilter = .nearest
        }
    }

    init(
        sourceView: NSView,
        sharedSurfaceCandidatesProvider: (@MainActor (NSView) -> [(NSView, CALayer)])? = nil
    ) {
        self.sourceView = sourceView
        self.sharedSurfaceCandidatesProvider = sharedSurfaceCandidatesProvider
        super.init(frame: sourceView.bounds)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = bounds
        addSubview(imageView)
        startMirroring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WorkspaceMapRuntimeInteractiveMirrorView")
    }

    deinit {
        refreshTimer?.invalidate()
        pendingBurstCaptureWorkItems.forEach { $0.cancel() }
        sharedSurfaceRootView = nil
        sharedSurfaceMirrors.forEach { $0.mirrorLayer.removeFromSuperlayer() }
        sharedSurfaceMirrors.removeAll()
        sharedSurfaceLayer.removeFromSuperlayer()
        sharedSurfaceLayer.contents = nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateRefreshCadence()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        updateRefreshCadence()
        return accepted
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        if !sharedSurfaceMirrors.isEmpty {
            syncSharedSurfaceLayerFrame()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if dispatchMouseEvent(.leftMouseDown, from: event) { return }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if dispatchMouseEvent(.leftMouseUp, from: event) { return }
        super.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if dispatchMouseEvent(.leftMouseDragged, from: event) { return }
        super.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if dispatchMouseEvent(.rightMouseDown, from: event) { return }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if dispatchMouseEvent(.rightMouseUp, from: event) { return }
        super.rightMouseUp(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if dispatchMouseEvent(.rightMouseDragged, from: event) { return }
        super.rightMouseDragged(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if dispatchMouseEvent(.otherMouseDown, from: event) { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if dispatchMouseEvent(.otherMouseUp, from: event) { return }
        super.otherMouseUp(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        if dispatchMouseEvent(.otherMouseDragged, from: event) { return }
        super.otherMouseDragged(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if dispatchMouseEvent(.mouseMoved, from: event) { return }
        super.mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if dispatchScrollEvent(from: event) { return }
        super.scrollWheel(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if dispatchKeyEvent(.keyDown, from: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if dispatchKeyEvent(.keyDown, from: event) { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if dispatchKeyEvent(.keyUp, from: event) { return }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if dispatchKeyEvent(.flagsChanged, from: event) { return }
        super.flagsChanged(with: event)
    }

    @objc
    func cut(_ sender: Any?) {
        if forwardAction(#selector(NSText.cut(_:)), sender: sender) { return }
        _ = nextResponder?.tryToPerform(#selector(NSText.cut(_:)), with: sender)
    }

    @objc
    func copy(_ sender: Any?) {
        if forwardAction(#selector(NSText.copy(_:)), sender: sender) { return }
        _ = nextResponder?.tryToPerform(#selector(NSText.copy(_:)), with: sender)
    }

    @objc
    func paste(_ sender: Any?) {
        if forwardAction(#selector(NSText.paste(_:)), sender: sender) { return }
        _ = nextResponder?.tryToPerform(#selector(NSText.paste(_:)), with: sender)
    }

    override func selectAll(_ sender: Any?) {
        if forwardAction(#selector(NSText.selectAll(_:)), sender: sender) { return }
        _ = nextResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: sender)
    }

    override var undoManager: UndoManager? {
        guard let sourceView, let sourceWindow = sourceView.window else {
            return super.undoManager
        }
        return sourceWindow.undoManager ?? super.undoManager
    }

    @objc
    func undo(_ sender: Any?) {
        if forwardAction(Self.undoSelector, sender: sender) { return }
        _ = nextResponder?.tryToPerform(Self.undoSelector, with: sender)
    }

    @objc
    func redo(_ sender: Any?) {
        if forwardAction(Self.redoSelector, sender: sender) { return }
        _ = nextResponder?.tryToPerform(Self.redoSelector, with: sender)
    }

    func stopMirroring() {
        guard isMirroringActive else { return }
        isMirroringActive = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancelPendingBurstCaptures()
        disableSharedSurfaceTransport()
        releaseForcedSurfaceFocusIfNeeded()
    }

    private func startMirroring() {
        guard !isMirroringActive else { return }
        isMirroringActive = true
        refreshInterval = preferredRefreshInterval()
        captureFrame()
        scheduleRefreshTimer()
    }

    private func captureFrame() {
        guard isMirroringActive else { return }
        guard let sourceView else { return }
        primeSurfaceRendererForCapture(sourceView: sourceView)
        if ensureSharedSurfaceTransport(sourceView: sourceView) {
            WorkspaceMapLiveCanvasRenderPathRecorder.recordSharedTransportFrame()
            syncSharedSurfaceLayerFrame()
            return
        }
        disableSharedSurfaceTransport()
        let sourceBounds = sourceView.bounds.integral
        guard sourceBounds.width > 1, sourceBounds.height > 1 else { return }
        CATransaction.flush()
        activeSurfaceView?.layoutSubtreeIfNeeded()
        activeSurfaceView?.displayIfNeeded()
        sourceView.layoutSubtreeIfNeeded()
        sourceView.displayIfNeeded()
        sourceView.window?.displayIfNeeded()
        guard let imageRep = sourceView.bitmapImageRepForCachingDisplay(in: sourceBounds) else { return }
        imageRep.size = sourceBounds.size
        sourceView.cacheDisplay(in: sourceBounds, to: imageRep)
        let image = NSImage(size: sourceBounds.size)
        image.addRepresentation(imageRep)
        imageView.image = image
        WorkspaceMapLiveCanvasRenderPathRecorder.recordBitmapFallbackFrame()
    }

    private func primeSurfaceRendererForCapture(sourceView: NSView) {
        if let activeSurface = resolveActiveSurfaceView(sourceView: sourceView) {
            requestImmediateSurfaceDraw(activeSurface)
        }

        // In tabbed-window background tabs, the renderer can throttle aggressively.
        // Prime every embedded surface to reduce stale frame captures in canvas mode.
        if sourceView.window?.isKeyWindow != true {
            collectSurfaceViews(in: sourceView).forEach(requestImmediateSurfaceDraw)
        }
    }

    private func requestImmediateSurfaceDraw(_ surfaceView: Ghostty.SurfaceView) {
        guard let surface = surfaceView.surface else { return }
        ghostty_surface_refresh(surface)
        ghostty_surface_draw(surface)
    }

    private func collectSurfaceViews(in root: NSView) -> [Ghostty.SurfaceView] {
        var result: [Ghostty.SurfaceView] = []
        if let surface = root as? Ghostty.SurfaceView {
            result.append(surface)
        }
        for child in root.subviews {
            result.append(contentsOf: collectSurfaceViews(in: child))
        }
        return result
    }

    private func resolveSharedSurfaceCandidates(in root: NSView) -> [SharedSurfaceCandidate] {
        if let sharedSurfaceCandidatesProvider {
            return sharedSurfaceCandidatesProvider(root).map { view, layer in
                SharedSurfaceCandidate(view: view, layer: layer)
            }
        }

        return collectSurfaceViews(in: root).compactMap { surfaceView in
            guard let layer = surfaceView.layer else { return nil }
            return SharedSurfaceCandidate(view: surfaceView, layer: layer)
        }
    }

    private func ensureSharedSurfaceTransport(sourceView: NSView) -> Bool {
        let surfaceCandidates = resolveSharedSurfaceCandidates(in: sourceView)
        guard !surfaceCandidates.isEmpty else {
            return false
        }

        if !sharedSurfaceMatches(surfaceCandidates, in: sourceView) {
            rebuildSharedSurfaceMirrors(from: surfaceCandidates, in: sourceView)
        }

        guard !sharedSurfaceMirrors.isEmpty else {
            return false
        }

        if sharedSurfaceLayer.superlayer == nil {
            layer?.addSublayer(sharedSurfaceLayer)
        }
        imageView.isHidden = true
        return true
    }

    private func sharedSurfaceMatches(_ surfaceCandidates: [SharedSurfaceCandidate], in sourceView: NSView) -> Bool {
        guard sharedSurfaceRootView === sourceView,
              sharedSurfaceMirrors.count == surfaceCandidates.count else {
            return false
        }
        for (index, sourceSurface) in surfaceCandidates.enumerated() {
            let mirror = sharedSurfaceMirrors[index]
            guard mirror.sourceView === sourceSurface.view,
                  mirror.sourceLayer === sourceSurface.layer else {
                return false
            }
        }
        return true
    }

    private func rebuildSharedSurfaceMirrors(from surfaceCandidates: [SharedSurfaceCandidate], in sourceView: NSView) {
        sharedSurfaceMirrors.forEach { $0.mirrorLayer.removeFromSuperlayer() }
        sharedSurfaceMirrors.removeAll()
        sharedSurfaceRootView = sourceView
        sharedSurfaceLayer.frame = bounds

        for sourceSurface in surfaceCandidates {
            let mirror = SharedSurfaceMirror(sourceView: sourceSurface.view, sourceLayer: sourceSurface.layer)
            mirror.mirrorLayer.contents = sourceSurface.layer.contents
            mirror.mirrorLayer.contentsScale = sourceSurface.layer.contentsScale
            sharedSurfaceLayer.addSublayer(mirror.mirrorLayer)
            sharedSurfaceMirrors.append(mirror)
        }
    }

    private func disableSharedSurfaceTransport() {
        sharedSurfaceRootView = nil
        sharedSurfaceMirrors.forEach { $0.mirrorLayer.removeFromSuperlayer() }
        sharedSurfaceMirrors.removeAll()
        sharedSurfaceLayer.removeFromSuperlayer()
        sharedSurfaceLayer.contents = nil
        imageView.isHidden = false
    }

    private func syncSharedSurfaceLayerFrame() {
        guard let sourceView else {
            sharedSurfaceLayer.frame = bounds
            return
        }

        let sourceBounds = sourceView.bounds
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            sharedSurfaceLayer.frame = bounds
            return
        }

        sharedSurfaceLayer.frame = bounds
        for mirror in sharedSurfaceMirrors {
            guard let sourceSurface = mirror.sourceView,
                  sourceSurface.isDescendant(of: sourceView),
                  let sourceLayer = mirror.sourceLayer else {
                mirror.mirrorLayer.isHidden = true
                continue
            }

            mirror.mirrorLayer.isHidden = false
            mirror.mirrorLayer.contents = sourceLayer.contents
            mirror.mirrorLayer.contentsScale = sourceLayer.contentsScale

            let surfaceRectInSource = sourceView.convert(sourceSurface.bounds, from: sourceSurface)
            let normalizedX = (surfaceRectInSource.minX - sourceBounds.minX) / sourceBounds.width
            let normalizedY = (surfaceRectInSource.minY - sourceBounds.minY) / sourceBounds.height
            let normalizedWidth = surfaceRectInSource.width / sourceBounds.width
            let normalizedHeight = surfaceRectInSource.height / sourceBounds.height
            mirror.mirrorLayer.frame = CGRect(
                x: bounds.width * normalizedX,
                y: bounds.height * normalizedY,
                width: bounds.width * normalizedWidth,
                height: bounds.height * normalizedHeight
            ).integral
        }
    }

    @objc
    private func handleRefreshTimer(_ timer: Timer) {
        guard timer === refreshTimer else { return }
        let expectedInterval = preferredRefreshInterval()
        if abs(expectedInterval - refreshInterval) > 0.001 {
            refreshInterval = expectedInterval
            scheduleRefreshTimer()
        }
        captureFrame()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(
            timeInterval: refreshInterval,
            target: self,
            selector: #selector(handleRefreshTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func preferredRefreshInterval() -> TimeInterval {
        if isInteractionBoostActive {
            return Self.interactionBoostRefreshInterval
        }
        return window?.firstResponder === self ? Self.focusedRefreshInterval : Self.idleRefreshInterval
    }

    private func updateRefreshCadence() {
        guard isMirroringActive else { return }
        let expectedInterval = preferredRefreshInterval()
        guard abs(expectedInterval - refreshInterval) > 0.001 else { return }
        refreshInterval = expectedInterval
        scheduleRefreshTimer()
    }

    private func dispatchMouseEvent(_ eventType: NSEvent.EventType, from event: NSEvent) -> Bool {
        guard let mappedPoints = mappedSourcePoints(from: event),
              let sourceView,
              let sourceWindow = sourceView.window,
              let mappedEvent = NSEvent.mouseEvent(
                  with: eventType,
                  location: mappedPoints.sourceWindowPoint,
                  modifierFlags: event.modifierFlags,
                  timestamp: event.timestamp,
                  windowNumber: sourceWindow.windowNumber,
                  context: nil,
                  eventNumber: event.eventNumber,
                  clickCount: event.clickCount,
                  pressure: event.pressure
              ) else {
            return false
        }

        lastInteractionSourcePoint = mappedPoints.sourceViewPoint
        let resolvedTarget = sourceView.hitTest(mappedPoints.sourceViewPoint) ?? sourceView
        if let surfaceView = resolveSurfaceView(from: resolvedTarget, sourceView: sourceView) {
            activeSurfaceView = surfaceView
            ensureSurfaceInputFocus(surfaceView)
        }
        let targetView: NSView
        switch eventType {
        case .leftMouseDown:
            leftDragTargetView = resolvedTarget
            keyboardTargetView = resolveKeyboardTarget(from: resolvedTarget, sourceView: sourceView)
            targetView = resolvedTarget
        case .leftMouseDragged:
            targetView = leftDragTargetView ?? resolvedTarget
        case .leftMouseUp:
            targetView = leftDragTargetView ?? resolvedTarget
            leftDragTargetView = nil
        case .rightMouseDown:
            rightDragTargetView = resolvedTarget
            keyboardTargetView = resolveKeyboardTarget(from: resolvedTarget, sourceView: sourceView)
            targetView = resolvedTarget
        case .rightMouseDragged:
            targetView = rightDragTargetView ?? resolvedTarget
        case .rightMouseUp:
            targetView = rightDragTargetView ?? resolvedTarget
            rightDragTargetView = nil
        case .otherMouseDown:
            otherDragTargetView = resolvedTarget
            keyboardTargetView = resolveKeyboardTarget(from: resolvedTarget, sourceView: sourceView)
            targetView = resolvedTarget
        case .otherMouseDragged:
            targetView = otherDragTargetView ?? resolvedTarget
        case .otherMouseUp:
            targetView = otherDragTargetView ?? resolvedTarget
            otherDragTargetView = nil
        case .mouseMoved:
            targetView = resolvedTarget
        default:
            targetView = resolvedTarget
        }

        switch eventType {
        case .leftMouseDown:
            targetView.mouseDown(with: mappedEvent)
        case .leftMouseDragged:
            targetView.mouseDragged(with: mappedEvent)
        case .leftMouseUp:
            targetView.mouseUp(with: mappedEvent)
        case .rightMouseDown:
            targetView.rightMouseDown(with: mappedEvent)
        case .rightMouseDragged:
            targetView.rightMouseDragged(with: mappedEvent)
        case .rightMouseUp:
            targetView.rightMouseUp(with: mappedEvent)
        case .otherMouseDown:
            targetView.otherMouseDown(with: mappedEvent)
        case .otherMouseDragged:
            targetView.otherMouseDragged(with: mappedEvent)
        case .otherMouseUp:
            targetView.otherMouseUp(with: mappedEvent)
        case .mouseMoved:
            targetView.mouseMoved(with: mappedEvent)
        default:
            return false
        }

        if eventType != .mouseMoved {
            triggerInteractiveCapture()
        }
        return true
    }

    private func dispatchScrollEvent(from event: NSEvent) -> Bool {
        guard let mappedPoints = mappedSourcePoints(from: event),
              let sourceView,
              let sourceWindow = sourceView.window else {
            return false
        }
        lastInteractionSourcePoint = mappedPoints.sourceViewPoint
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: event.hasPreciseScrollingDeltas ? .pixel : .line,
            wheelCount: 2,
            wheel1: Int32(event.scrollingDeltaY.rounded()),
            wheel2: Int32(event.scrollingDeltaX.rounded()),
            wheel3: 0
        ) else {
            return false
        }
        cgEvent.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        cgEvent.setIntegerValueField(
            .scrollWheelEventIsContinuous,
            value: event.hasPreciseScrollingDeltas ? 1 : 0
        )
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(event.scrollingDeltaY))
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(event.scrollingDeltaX))
        cgEvent.location = sourceWindow.convertPoint(toScreen: mappedPoints.sourceWindowPoint)
        guard let mappedEvent = NSEvent(cgEvent: cgEvent) else {
            return false
        }

        let targetView = sourceView.hitTest(mappedPoints.sourceViewPoint) ?? sourceView
        if let surfaceView = resolveSurfaceView(from: targetView, sourceView: sourceView) {
            activeSurfaceView = surfaceView
            ensureSurfaceInputFocus(surfaceView)
        }
        keyboardTargetView = resolveKeyboardTarget(from: targetView, sourceView: sourceView)
        targetView.scrollWheel(with: mappedEvent)
        triggerInteractiveCapture()
        return true
    }

    private func dispatchKeyEvent(_ eventType: NSEvent.EventType, from event: NSEvent) -> Bool {
        guard let sourceView,
              let sourceWindow = sourceView.window,
              let mappedEvent = NSEvent.keyEvent(
                  with: eventType,
                  location: sourceWindow.mouseLocationOutsideOfEventStream,
                  modifierFlags: event.modifierFlags,
                  timestamp: event.timestamp,
                  windowNumber: sourceWindow.windowNumber,
                  context: nil,
                  characters: event.characters ?? "",
                  charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                  isARepeat: event.isARepeat,
                  keyCode: event.keyCode
              ) else {
            return false
        }

        if let surfaceView = resolveActiveSurfaceView(sourceView: sourceView) {
            ensureSurfaceInputFocus(surfaceView)
            switch eventType {
            case .keyDown:
                surfaceView.keyDown(with: mappedEvent)
            case .keyUp:
                surfaceView.keyUp(with: mappedEvent)
            case .flagsChanged:
                surfaceView.flagsChanged(with: mappedEvent)
            default:
                break
            }
            triggerInteractiveCapture()
            return true
        }

        let keyTarget = resolveKeyResponder(sourceView: sourceView, sourceWindow: sourceWindow)
        if let keyTargetView = keyTarget as? NSView,
           keyTargetView.window === sourceWindow,
           (sourceWindow.firstResponder as? NSView) !== keyTargetView {
            _ = sourceWindow.makeFirstResponder(keyTargetView)
        }

        switch eventType {
        case .keyDown:
            keyTarget.keyDown(with: mappedEvent)
        case .keyUp:
            keyTarget.keyUp(with: mappedEvent)
        case .flagsChanged:
            keyTarget.flagsChanged(with: mappedEvent)
        default:
            return false
        }

        triggerInteractiveCapture()
        return true
    }

    private func ensureSurfaceInputFocus(_ surfaceView: Ghostty.SurfaceView) {
        if forcedFocusedSurfaceView !== surfaceView {
            releaseForcedSurfaceFocusIfNeeded()
            forcedFocusedSurfaceView = surfaceView
        }
        if !surfaceView.focused {
            surfaceView.focusDidChange(true)
        }
    }

    private func releaseForcedSurfaceFocusIfNeeded() {
        guard let surfaceView = forcedFocusedSurfaceView else { return }
        if !((surfaceView.window?.isKeyWindow) ?? false) {
            surfaceView.focusDidChange(false)
        }
        forcedFocusedSurfaceView = nil
    }

    private func resolveActiveSurfaceView(sourceView: NSView) -> Ghostty.SurfaceView? {
        if let activeSurfaceView,
           activeSurfaceView.isDescendant(of: sourceView) {
            return activeSurfaceView
        }

        if let keyboardTargetView,
           let surfaceView = resolveSurfaceView(from: keyboardTargetView, sourceView: sourceView) {
            activeSurfaceView = surfaceView
            return surfaceView
        }

        if let lastInteractionSourcePoint,
           let hitView = sourceView.hitTest(lastInteractionSourcePoint),
           let surfaceView = resolveSurfaceView(from: hitView, sourceView: sourceView) {
            activeSurfaceView = surfaceView
            return surfaceView
        }

        if let firstSurface = firstDescendant(in: sourceView, matching: { $0 is Ghostty.SurfaceView }) as? Ghostty.SurfaceView {
            activeSurfaceView = firstSurface
            return firstSurface
        }
        return nil
    }

    private func resolveSurfaceView(from view: NSView, sourceView: NSView) -> Ghostty.SurfaceView? {
        guard view.isDescendant(of: sourceView) || view === sourceView else { return nil }
        var current: NSView? = view
        while let node = current {
            if let surfaceView = node as? Ghostty.SurfaceView {
                return surfaceView
            }
            if node === sourceView {
                break
            }
            current = node.superview
        }
        return nil
    }

    private func resolveKeyResponder(sourceView: NSView, sourceWindow: NSWindow) -> NSResponder {
        if let firstResponderView = sourceWindow.firstResponder as? NSView,
           firstResponderView.isDescendant(of: sourceView) {
            return firstResponderView
        }

        if let keyboardTargetView,
           keyboardTargetView.isDescendant(of: sourceView) {
            return keyboardTargetView
        }

        if let lastInteractionSourcePoint,
           let hitView = sourceView.hitTest(lastInteractionSourcePoint),
           let target = resolveKeyboardTarget(from: hitView, sourceView: sourceView) {
            keyboardTargetView = target
            return target
        }

        if let fallback = firstDescendant(in: sourceView, matching: { $0.acceptsFirstResponder }) {
            keyboardTargetView = fallback
            return fallback
        }

        return sourceView
    }

    private func resolveKeyboardTarget(from view: NSView, sourceView: NSView) -> NSView? {
        guard view.isDescendant(of: sourceView) || view === sourceView else { return nil }

        var current: NSView? = view
        while let node = current {
            if node.acceptsFirstResponder {
                return node
            }
            if node === sourceView {
                break
            }
            current = node.superview
        }

        return view
    }

    private func firstDescendant(
        in root: NSView,
        matching predicate: (NSView) -> Bool
    ) -> NSView? {
        if predicate(root) {
            return root
        }

        for child in root.subviews {
            if let match = firstDescendant(in: child, matching: predicate) {
                return match
            }
        }
        return nil
    }

    @discardableResult
    private func forwardAction(_ selector: Selector, sender: Any?) -> Bool {
        guard let sourceView, let sourceWindow = sourceView.window else { return false }
        if (sourceWindow.firstResponder as? NSView)?.isDescendant(of: sourceView) != true {
            _ = sourceWindow.makeFirstResponder(sourceView)
        }
        if let responder = sourceWindow.firstResponder, responder.tryToPerform(selector, with: sender) {
            triggerInteractiveCapture()
            return true
        }
        if sourceView.tryToPerform(selector, with: sender) {
            triggerInteractiveCapture()
            return true
        }
        if sourceWindow.tryToPerform(selector, with: sender) {
            triggerInteractiveCapture()
            return true
        }
        return false
    }

    private var isInteractionBoostActive: Bool {
        CFAbsoluteTimeGetCurrent() < interactionBoostUntil
    }

    private func triggerInteractiveCapture() {
        bumpInteractionBoostWindow()
        captureFrame()
        scheduleBurstCaptures()
    }

    private func bumpInteractionBoostWindow() {
        interactionBoostUntil = CFAbsoluteTimeGetCurrent() + Self.interactionBoostDuration
        updateRefreshCadence()
    }

    private func scheduleBurstCaptures() {
        cancelPendingBurstCaptures()
        for delay in Self.interactionBurstDelays {
            let workItem = DispatchWorkItem { [weak self] in
                self?.captureFrame()
            }
            pendingBurstCaptureWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelPendingBurstCaptures() {
        pendingBurstCaptureWorkItems.forEach { $0.cancel() }
        pendingBurstCaptureWorkItems.removeAll()
    }

    private struct WorkspaceMapMappedPoints {
        let sourceViewPoint: CGPoint
        let sourceWindowPoint: CGPoint
    }

    private func mappedSourcePoints(from event: NSEvent) -> WorkspaceMapMappedPoints? {
        guard let sourceView else { return nil }
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let localPoint = convert(event.locationInWindow, from: nil)
        let normalizedX = max(min(localPoint.x / bounds.width, 1), 0)
        let normalizedY = max(min(localPoint.y / bounds.height, 1), 0)
        let sourceBounds = sourceView.bounds
        let sourcePoint = CGPoint(
            x: sourceBounds.minX + sourceBounds.width * normalizedX,
            y: sourceBounds.minY + sourceBounds.height * normalizedY
        )
        return WorkspaceMapMappedPoints(
            sourceViewPoint: sourcePoint,
            sourceWindowPoint: sourceView.convert(sourcePoint, to: nil)
        )
    }
}
