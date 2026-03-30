import AppKit

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
    private static let refreshInterval: TimeInterval = 1.0 / 10.0

    private weak var sourceView: NSView?
    private let imageView = NSImageView(frame: .zero)
    private var refreshTimer: Timer?
    private(set) var isMirroringActive = false

    init(sourceView: NSView) {
        self.sourceView = sourceView
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
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        imageView.frame = bounds
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

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if dispatchMouseEvent(.otherMouseDown, from: event) { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if dispatchMouseEvent(.otherMouseUp, from: event) { return }
        super.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if dispatchScrollEvent(from: event) { return }
        super.scrollWheel(with: event)
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

    func stopMirroring() {
        guard isMirroringActive else { return }
        isMirroringActive = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startMirroring() {
        guard !isMirroringActive else { return }
        isMirroringActive = true
        captureFrame()
        let timer = Timer.scheduledTimer(
            timeInterval: Self.refreshInterval,
            target: self,
            selector: #selector(handleRefreshTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func captureFrame() {
        guard isMirroringActive else { return }
        guard let sourceView else { return }
        let sourceBounds = sourceView.bounds.integral
        guard sourceBounds.width > 1, sourceBounds.height > 1 else { return }
        guard let imageRep = sourceView.bitmapImageRepForCachingDisplay(in: sourceBounds) else { return }
        imageRep.size = sourceBounds.size
        sourceView.cacheDisplay(in: sourceBounds, to: imageRep)
        let image = NSImage(size: sourceBounds.size)
        image.addRepresentation(imageRep)
        imageView.image = image
    }

    @objc
    private func handleRefreshTimer(_ timer: Timer) {
        captureFrame()
    }

    private func dispatchMouseEvent(_ eventType: NSEvent.EventType, from event: NSEvent) -> Bool {
        guard let sourceWindowPoint = mappedSourceWindowPoint(from: event),
              let sourceView,
              let sourceWindow = sourceView.window,
              let mappedEvent = NSEvent.mouseEvent(
                  with: eventType,
                  location: sourceWindowPoint,
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
        sourceWindow.sendEvent(mappedEvent)
        return true
    }

    private func dispatchScrollEvent(from event: NSEvent) -> Bool {
        guard let sourceWindowPoint = mappedSourceWindowPoint(from: event),
              let sourceView,
              let sourceWindow = sourceView.window else {
            return false
        }
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
        cgEvent.location = sourceWindow.convertPoint(toScreen: sourceWindowPoint)
        guard let mappedEvent = NSEvent(cgEvent: cgEvent) else {
            return false
        }
        sourceWindow.sendEvent(mappedEvent)
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
        sourceWindow.sendEvent(mappedEvent)
        return true
    }

    private func mappedSourceWindowPoint(from event: NSEvent) -> CGPoint? {
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
        return sourceView.convert(sourcePoint, to: nil)
    }
}
