import XCTest
import AppKit
@testable import GhoDex

@MainActor
final class WorkspaceMapLiveCanvasContentProviderTests: XCTestCase {
    func testAcquireLeaseUsesMirrorWithoutMutatingSourceWindowOwnership() {
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
            guard let mirror = lease.borrowedView as? WorkspaceMapRuntimeLiveMirrorView else {
                XCTFail("Expected runtime mirror lease view")
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
            guard let mirror = lease.borrowedView as? WorkspaceMapRuntimeLiveMirrorView else {
                XCTFail("Expected runtime mirror lease view")
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
}
