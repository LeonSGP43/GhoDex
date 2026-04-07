import XCTest
import AppKit
@testable import GhoDex

@MainActor
final class WorkspaceMapLiveCanvasContentProviderTests: XCTestCase {
    func testAcquireLeaseUsesInteractiveMirrorWithoutMutatingSourceWindowOwnership() {
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sourceView = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        sourceWindow.contentView = sourceView

        let provider = WorkspaceMapRuntimeLiveCanvasContentProvider(
            sourceViewResolver: { _ in sourceView }
        )

        let result = provider.acquireLease(for: makeTerminalGroup())
        switch result {
        case .lease(let lease):
            XCTAssertTrue(sourceWindow.contentView === sourceView)
            XCTAssertFalse(lease.borrowedView === sourceView)
            guard let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView else {
                XCTFail("Expected runtime interactive mirror lease view")
                return
            }
            XCTAssertTrue(mirror.isMirroringActive)
            lease.release()
            XCTAssertTrue(sourceWindow.contentView === sourceView)
            XCTAssertFalse(mirror.isMirroringActive)
        case .unavailable(let message):
            XCTFail("Expected lease, got unavailable: \(message)")
        }
    }

    func testLeaseReleaseIsIdempotent() {
        let sourceView = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 440))
        let provider = WorkspaceMapRuntimeLiveCanvasContentProvider(
            sourceViewResolver: { _ in sourceView }
        )

        let result = provider.acquireLease(for: makeTerminalGroup())
        switch result {
        case .lease(let lease):
            guard let mirror = lease.borrowedView as? WorkspaceMapRuntimeInteractiveMirrorView else {
                XCTFail("Expected runtime interactive mirror lease view")
                return
            }
            XCTAssertTrue(mirror.isMirroringActive)
            lease.release()
            XCTAssertFalse(mirror.isMirroringActive)
            lease.release()
            XCTAssertFalse(mirror.isMirroringActive)
        case .unavailable(let message):
            XCTFail("Expected lease, got unavailable: \(message)")
        }
    }

    func testMirrorForwardsCommonEditActionsToSourceResponder() {
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sourceView = ActionCaptureView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        sourceWindow.contentView = sourceView
        XCTAssertTrue(sourceWindow.makeFirstResponder(sourceView))

        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(sourceView: sourceView)
        XCTAssertTrue(mirror.acceptsFirstMouse(for: nil))

        mirror.copy(nil)
        mirror.paste(nil)
        mirror.selectAll(nil)
        mirror.undo(nil)
        mirror.redo(nil)

        XCTAssertEqual(sourceView.copyCount, 1)
        XCTAssertEqual(sourceView.pasteCount, 1)
        XCTAssertEqual(sourceView.selectAllCount, 1)
        XCTAssertEqual(sourceView.undoCount, 1)
        XCTAssertEqual(sourceView.redoCount, 1)

        mirror.stopMirroring()
    }

    func testMirrorRoutesKeyboardInputToLastMouseHitDescendant() throws {
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        let keyCaptureView = KeyCaptureView(frame: rootView.bounds)
        keyCaptureView.autoresizingMask = [.width, .height]
        rootView.addSubview(keyCaptureView)
        sourceWindow.contentView = rootView

        let mirrorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(sourceView: rootView)
        mirror.frame = mirrorWindow.contentView?.bounds ?? .zero
        mirror.autoresizingMask = [.width, .height]
        mirrorWindow.contentView = mirror

        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 220, y: 140),
                modifierFlags: [],
                timestamp: 1,
                windowNumber: mirrorWindow.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        mirror.mouseDown(with: mouseDown)

        let keyDown = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: NSPoint(x: 220, y: 140),
                modifierFlags: [],
                timestamp: 2,
                windowNumber: mirrorWindow.windowNumber,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )
        mirror.keyDown(with: keyDown)

        XCTAssertEqual(keyCaptureView.mouseDownCount, 1)
        XCTAssertEqual(keyCaptureView.keyDownCount, 1)
        mirror.stopMirroring()
    }

    func testMirrorRoutesRightMouseDragToLastMouseHitDescendant() throws {
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        let captureView = MouseButtonCaptureView(frame: rootView.bounds)
        captureView.autoresizingMask = [.width, .height]
        rootView.addSubview(captureView)
        sourceWindow.contentView = rootView

        let mirrorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(sourceView: rootView)
        mirror.frame = mirrorWindow.contentView?.bounds ?? .zero
        mirror.autoresizingMask = [.width, .height]
        mirrorWindow.contentView = mirror

        mirror.rightMouseDown(with: try makeMouseEvent(type: .rightMouseDown, timestamp: 1, windowNumber: mirrorWindow.windowNumber))
        mirror.rightMouseDragged(with: try makeMouseEvent(type: .rightMouseDragged, timestamp: 2, windowNumber: mirrorWindow.windowNumber, location: NSPoint(x: 240, y: 120)))
        mirror.rightMouseUp(with: try makeMouseEvent(type: .rightMouseUp, timestamp: 3, windowNumber: mirrorWindow.windowNumber, location: NSPoint(x: 240, y: 120)))

        XCTAssertEqual(captureView.rightMouseDownCount, 1)
        XCTAssertEqual(captureView.rightMouseDraggedCount, 1)
        XCTAssertEqual(captureView.rightMouseUpCount, 1)
        mirror.stopMirroring()
    }

    func testMirrorRoutesOtherMouseDragToLastMouseHitDescendant() throws {
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 560))
        let captureView = MouseButtonCaptureView(frame: rootView.bounds)
        captureView.autoresizingMask = [.width, .height]
        rootView.addSubview(captureView)
        sourceWindow.contentView = rootView

        let mirrorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(sourceView: rootView)
        mirror.frame = mirrorWindow.contentView?.bounds ?? .zero
        mirror.autoresizingMask = [.width, .height]
        mirrorWindow.contentView = mirror

        mirror.otherMouseDown(with: try makeMouseEvent(type: .otherMouseDown, timestamp: 1, windowNumber: mirrorWindow.windowNumber))
        mirror.otherMouseDragged(with: try makeMouseEvent(type: .otherMouseDragged, timestamp: 2, windowNumber: mirrorWindow.windowNumber, location: NSPoint(x: 240, y: 120)))
        mirror.otherMouseUp(with: try makeMouseEvent(type: .otherMouseUp, timestamp: 3, windowNumber: mirrorWindow.windowNumber, location: NSPoint(x: 240, y: 120)))

        XCTAssertEqual(captureView.otherMouseDownCount, 1)
        XCTAssertEqual(captureView.otherMouseDraggedCount, 1)
        XCTAssertEqual(captureView.otherMouseUpCount, 1)
        mirror.stopMirroring()
    }

    func testBrowserGroupIsRejectedBeforeResolverLookup() {
        var resolverCallCount = 0
        let provider = WorkspaceMapRuntimeLiveCanvasContentProvider(
            sourceViewResolver: { _ in
                resolverCallCount += 1
                return nil
            }
        )

        let result = provider.acquireLease(for: makeBrowserGroup())
        switch result {
        case .lease:
            XCTFail("Browser group must not receive live lease in v1")
        case .unavailable:
            XCTAssertEqual(resolverCallCount, 0)
        }
    }

    func testTerminalGroupIsUnavailableWhenSourceViewMissing() {
        let provider = WorkspaceMapRuntimeLiveCanvasContentProvider(
            sourceViewResolver: { _ in nil }
        )

        let result = provider.acquireLease(for: makeTerminalGroup())
        switch result {
        case .lease:
            XCTFail("Expected terminal group to be unavailable when source view is absent")
        case .unavailable(let message):
            XCTAssertEqual(message, "Terminal unavailable")
        }
    }

    func testRenderPathMetricsRecordBitmapFallbackFrames() {
        WorkspaceMapLiveCanvasRenderPathRecorder.reset()
        let sourceView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(sourceView: sourceView)
        mirror.stopMirroring()

        let metrics = WorkspaceMapLiveCanvasRenderPathRecorder.snapshot()
        XCTAssertGreaterThanOrEqual(metrics.bitmapFallbackFrameCount, 1)
        XCTAssertEqual(metrics.sharedTransportFrameCount, 0)
        XCTAssertEqual(metrics.totalFrameCount, metrics.bitmapFallbackFrameCount)
        XCTAssertEqual(metrics.sharedTransportHitRate, 0)
    }

    func testRenderPathMetricsRecordSharedTransportFramesWithInjectedCandidates() {
        WorkspaceMapLiveCanvasRenderPathRecorder.reset()
        let sourceView = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        sourceView.wantsLayer = true
        sourceView.layer = CALayer()
        let candidate = NSView(frame: sourceView.bounds)
        candidate.wantsLayer = true
        candidate.layer = CALayer()
        sourceView.addSubview(candidate)

        let mirror = WorkspaceMapRuntimeInteractiveMirrorView(
            sourceView: sourceView,
            sharedSurfaceCandidatesProvider: { _ in
                guard let layer = candidate.layer else { return [] }
                return [(candidate, layer)]
            }
        )
        mirror.stopMirroring()

        let metrics = WorkspaceMapLiveCanvasRenderPathRecorder.snapshot()
        XCTAssertGreaterThanOrEqual(metrics.sharedTransportFrameCount, 1)
        XCTAssertEqual(metrics.bitmapFallbackFrameCount, 0)
        XCTAssertEqual(metrics.totalFrameCount, metrics.sharedTransportFrameCount)
        XCTAssertEqual(metrics.sharedTransportHitRate, 1)
    }

    private func makeTerminalGroup() -> WorkspaceMapGroupSnapshot {
        WorkspaceMapGroupSnapshot(
            id: WorkspaceMapEntityID("terminal-group:11111111-1111-1111-1111-111111111111"),
            kind: .terminal,
            title: "Terminal",
            isFocused: true,
            terminal: WorkspaceMapTerminalGroupSnapshot(
                rootNodeID: nil,
                splitCount: 0,
                paneCount: 0,
                tabCount: 0,
                nodes: []
            ),
            browser: nil
        )
    }

    private func makeBrowserGroup() -> WorkspaceMapGroupSnapshot {
        WorkspaceMapGroupSnapshot(
            id: WorkspaceMapEntityID("browser-group:11111111-1111-1111-1111-111111111111"),
            kind: .browser,
            title: "Browser",
            isFocused: false,
            terminal: nil,
            browser: WorkspaceMapBrowserGroupSnapshot(
                selectedPageID: "page-1",
                displayedURL: "https://example.com"
            )
        )
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        timestamp: TimeInterval,
        windowNumber: Int,
        location: NSPoint = NSPoint(x: 220, y: 140)
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: Int(timestamp),
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private final class ActionCaptureView: NSView {
        var copyCount = 0
        var pasteCount = 0
        var selectAllCount = 0
        var undoCount = 0
        var redoCount = 0

        override var acceptsFirstResponder: Bool { true }

        @objc
        func copy(_ sender: Any?) {
            copyCount += 1
        }

        @objc
        func paste(_ sender: Any?) {
            pasteCount += 1
        }

        override func selectAll(_ sender: Any?) {
            selectAllCount += 1
        }

        @objc
        func undo(_ sender: Any?) {
            undoCount += 1
        }

        @objc
        func redo(_ sender: Any?) {
            redoCount += 1
        }
    }

    private final class KeyCaptureView: NSView {
        var mouseDownCount = 0
        var keyDownCount = 0

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownCount += 1
        }

        override func keyDown(with event: NSEvent) {
            keyDownCount += 1
        }
    }

    private final class MouseButtonCaptureView: NSView {
        var rightMouseDownCount = 0
        var rightMouseDraggedCount = 0
        var rightMouseUpCount = 0
        var otherMouseDownCount = 0
        var otherMouseDraggedCount = 0
        var otherMouseUpCount = 0

        override func rightMouseDown(with event: NSEvent) {
            rightMouseDownCount += 1
        }

        override func rightMouseDragged(with event: NSEvent) {
            rightMouseDraggedCount += 1
        }

        override func rightMouseUp(with event: NSEvent) {
            rightMouseUpCount += 1
        }

        override func otherMouseDown(with event: NSEvent) {
            otherMouseDownCount += 1
        }

        override func otherMouseDragged(with event: NSEvent) {
            otherMouseDraggedCount += 1
        }

        override func otherMouseUp(with event: NSEvent) {
            otherMouseUpCount += 1
        }
    }
}
