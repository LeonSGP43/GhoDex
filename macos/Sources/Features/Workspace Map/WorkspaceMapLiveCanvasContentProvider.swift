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
    typealias MirrorViewFactory = @MainActor (NSView) -> WorkspaceMapRuntimeLiveMirrorView

    private let sourceViewResolver: SourceViewResolver
    private let mirrorViewFactory: MirrorViewFactory

    init(
        sourceViewResolver: @escaping SourceViewResolver = { groupID in
            WorkspaceMapRuntimeLiveCanvasContentProvider.defaultSourceView(groupID)
        },
        mirrorViewFactory: @escaping MirrorViewFactory = { WorkspaceMapRuntimeLiveMirrorView(sourceView: $0) }
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
final class WorkspaceMapRuntimeLiveMirrorView: NSView {
    private static let refreshInterval: TimeInterval = 1.0 / 6.0

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
        fatalError("init(coder:) is not supported for WorkspaceMapRuntimeLiveMirrorView")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
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
}
