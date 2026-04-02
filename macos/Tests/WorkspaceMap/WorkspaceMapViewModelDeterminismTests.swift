import XCTest
import Foundation
import Combine
import CoreGraphics
@testable import GhoDex

@MainActor
final class WorkspaceMapViewModelDeterminismTests: XCTestCase {
    func testRefreshIgnoresGeneratedAtOnlyChanges() {
        let group = makeTerminalGroup(idToken: "11111111-1111-1111-1111-111111111111")
        var invocation = 0
        let model = WorkspaceMapViewModel(
            projectionSource: {
                invocation += 1
                return WorkspaceMapSnapshot(
                    generatedAt: Date(timeIntervalSince1970: TimeInterval(invocation)),
                    groups: [group]
                )
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: UserDefaults(suiteName: "WorkspaceMapViewModelDeterminismTests.refresh")!,
                storageKey: UUID().uuidString
            )
        )

        model.refresh()
        let firstTimestamp = model.snapshot.generatedAt
        model.refresh()

        XCTAssertEqual(firstTimestamp, model.snapshot.generatedAt)
        XCTAssertEqual(invocation, 2)
    }

    func testScheduleRefreshCoalescesBurstIntoSingleProjectionCall() async {
        var invocation = 0
        let model = WorkspaceMapViewModel(
            projectionSource: {
                invocation += 1
                return WorkspaceMapSnapshot(
                    generatedAt: Date(timeIntervalSince1970: 1),
                    groups: [self.makeTerminalGroup(idToken: "22222222-2222-2222-2222-222222222222")]
                )
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: UserDefaults(suiteName: "WorkspaceMapViewModelDeterminismTests.coalesce")!,
                storageKey: UUID().uuidString
            )
        )

        for _ in 0..<200 {
            model.scheduleRefresh()
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(invocation, 1)
    }

    func testCanvasPresentationActiveStartsPeriodicRefreshAndStopsWhenInactive() async {
        let suiteName = "WorkspaceMapViewModelDeterminismTests.canvas-refresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var invocation = 0
        let model = WorkspaceMapViewModel(
            projectionSource: {
                invocation += 1
                return WorkspaceMapSnapshot(
                    generatedAt: Date(timeIntervalSince1970: TimeInterval(invocation)),
                    groups: [self.makeTerminalGroup(idToken: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
                )
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            )
        )

        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertEqual(invocation, 0)

        model.setCanvasPresentationActive(true)
        try? await Task.sleep(nanoseconds: 520_000_000)
        XCTAssertGreaterThanOrEqual(invocation, 2)

        model.setCanvasPresentationActive(false)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let stoppedCount = invocation
        try? await Task.sleep(nanoseconds: 360_000_000)
        XCTAssertEqual(invocation, stoppedCount)
    }

    func testExecuteUpdatesLastCommandResultAndRefreshes() {
        var refreshCalls = 0
        let model = WorkspaceMapViewModel(
            projectionSource: {
                refreshCalls += 1
                return WorkspaceMapSnapshot(
                    generatedAt: Date(timeIntervalSince1970: 2),
                    groups: [self.makeTerminalGroup(idToken: "33333333-3333-3333-3333-333333333333")]
                )
            },
            commandExecutor: { request in
                WorkspaceMapCommandResult(
                    status: .executed,
                    message: "executed \(request.command.rawValue)"
                )
            },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: UserDefaults(suiteName: "WorkspaceMapViewModelDeterminismTests.execute")!,
                storageKey: UUID().uuidString
            )
        )

        model.execute(
            .focusTopLevelGroup,
            targetID: WorkspaceMapEntityID("terminal-group:33333333-3333-3333-3333-333333333333")
        )

        XCTAssertEqual(model.lastCommandResult?.status, .executed)
        XCTAssertEqual(model.lastCommandResult?.message, "executed focusTopLevelGroup")
        XCTAssertEqual(refreshCalls, 1)
    }

    func testAutoLayoutGroupsDoesNotProduceOverlappingFrames() {
        let suiteName = "WorkspaceMapViewModelDeterminismTests.auto-layout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let groups: [WorkspaceMapGroupSnapshot] = [
            makeTerminalGroup(idToken: "10000000-0000-0000-0000-000000000001"),
            makeTerminalGroup(idToken: "10000000-0000-0000-0000-000000000002"),
            makeTerminalGroup(idToken: "10000000-0000-0000-0000-000000000003"),
            makeTerminalGroup(idToken: "10000000-0000-0000-0000-000000000004"),
            makeBrowserGroup(idToken: "20000000-0000-0000-0000-000000000001"),
            makeBrowserGroup(idToken: "20000000-0000-0000-0000-000000000002"),
            makeBrowserGroup(idToken: "20000000-0000-0000-0000-000000000003"),
        ]

        let model = WorkspaceMapViewModel(
            projectionSource: {
                WorkspaceMapSnapshot(groups: groups)
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            )
        )

        model.refresh()
        model.autoLayoutGroups()

        let layoutByID = Dictionary(uniqueKeysWithValues: model.layout.groups.map { ($0.id, $0) })
        let frames: [CGRect] = groups.compactMap { group in
            guard let layout = layoutByID[group.id] else { return nil }
            let baseSize = baseSize(for: group.kind)
            return CGRect(
                x: layout.centerX - baseSize.width / 2,
                y: layout.centerY - baseSize.height / 2,
                width: baseSize.width,
                height: baseSize.height
            )
        }

        for index in 0..<frames.count {
            for other in (index + 1)..<frames.count {
                XCTAssertFalse(
                    frames[index].intersects(frames[other]),
                    "autoLayoutGroups produced overlapping frames: index \(index) and \(other)"
                )
            }
        }
    }

    func testAutoLayoutGroupsUsesMeasuredSizeHintsWithoutOverlapAndWithGap() {
        let suiteName = "WorkspaceMapViewModelDeterminismTests.auto-layout-hints.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let groups: [WorkspaceMapGroupSnapshot] = [
            makeTerminalGroup(idToken: "30000000-0000-0000-0000-000000000001"),
            makeTerminalGroup(idToken: "30000000-0000-0000-0000-000000000002"),
            makeTerminalGroup(idToken: "30000000-0000-0000-0000-000000000003"),
            makeBrowserGroup(idToken: "40000000-0000-0000-0000-000000000001"),
            makeBrowserGroup(idToken: "40000000-0000-0000-0000-000000000002"),
        ]

        let model = WorkspaceMapViewModel(
            projectionSource: {
                WorkspaceMapSnapshot(groups: groups)
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            )
        )

        model.refresh()

        let hintByID: [WorkspaceMapEntityID: CGSize] = [
            groups[0].id: CGSize(width: 1_420, height: 900),
            groups[1].id: CGSize(width: 1_360, height: 860),
            groups[2].id: CGSize(width: 1_480, height: 960),
            groups[3].id: CGSize(width: 1_540, height: 1_020),
            groups[4].id: CGSize(width: 1_500, height: 980),
        ]
        hintByID.forEach { groupID, size in
            model.updateGroupBaseSizeHint(groupID, size: size)
        }

        model.autoLayoutGroups()

        let layoutByID = Dictionary(uniqueKeysWithValues: model.layout.groups.map { ($0.id, $0) })
        let frames: [CGRect] = groups.compactMap { group in
            guard let layout = layoutByID[group.id] else { return nil }
            let baseSize = hintByID[group.id] ?? baseSize(for: group.kind)
            return CGRect(
                x: layout.centerX - baseSize.width / 2,
                y: layout.centerY - baseSize.height / 2,
                width: baseSize.width,
                height: baseSize.height
            )
        }

        let minimumGap: CGFloat = 80
        for index in 0..<frames.count {
            for other in (index + 1)..<frames.count {
                XCTAssertFalse(
                    frames[index].intersects(frames[other]),
                    "autoLayoutGroups with hints produced overlap: index \(index) and \(other)"
                )

                let (xGap, yGap) = gapBetween(frames[index], frames[other])
                XCTAssertTrue(
                    xGap >= minimumGap || yGap >= minimumGap,
                    "Expected at least \(minimumGap)pt gap, got xGap=\(xGap), yGap=\(yGap) for \(index)-\(other)"
                )
            }
        }
    }

    func testPlaceNewGroupsWithoutOverlapKeepsExistingLayoutStable() {
        let suiteName = "WorkspaceMapViewModelDeterminismTests.place-new-groups.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let existingA = makeTerminalGroup(idToken: "50000000-0000-0000-0000-000000000001")
        let existingB = makeTerminalGroup(idToken: "50000000-0000-0000-0000-000000000002")
        let incoming = makeTerminalGroup(idToken: "50000000-0000-0000-0000-000000000003")
        var sourceGroups: [WorkspaceMapGroupSnapshot] = [existingA, existingB]

        let model = WorkspaceMapViewModel(
            projectionSource: { WorkspaceMapSnapshot(groups: sourceGroups) },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            )
        )

        model.refresh()
        // Force one existing group onto the default spawn slot so the incoming
        // group would overlap unless the non-overlap placement kicks in.
        model.setGroupPosition(existingA.id, point: CGPoint(x: 560, y: 380))
        model.setGroupPosition(existingB.id, point: CGPoint(x: 1620, y: 380))

        let previousIDs: Set<WorkspaceMapEntityID> = [existingA.id, existingB.id]
        sourceGroups = [existingA, existingB, incoming]
        model.refresh()

        model.placeNewGroupsWithoutOverlap(previousGroupIDs: previousIDs)

        XCTAssertEqual(model.groupPosition(for: existingA.id), CGPoint(x: 560, y: 380))
        XCTAssertEqual(model.groupPosition(for: existingB.id), CGPoint(x: 1620, y: 380))

        let layoutByID = Dictionary(uniqueKeysWithValues: model.layout.groups.map { ($0.id, $0) })
        let existingAFrame = CGRect(
            x: (layoutByID[existingA.id]?.centerX ?? 0) - 880 / 2,
            y: (layoutByID[existingA.id]?.centerY ?? 0) - 560 / 2,
            width: 880,
            height: 560
        )
        let existingBFrame = CGRect(
            x: (layoutByID[existingB.id]?.centerX ?? 0) - 880 / 2,
            y: (layoutByID[existingB.id]?.centerY ?? 0) - 560 / 2,
            width: 880,
            height: 560
        )
        let incomingFrame = CGRect(
            x: (layoutByID[incoming.id]?.centerX ?? 0) - 880 / 2,
            y: (layoutByID[incoming.id]?.centerY ?? 0) - 560 / 2,
            width: 880,
            height: 560
        )

        XCTAssertFalse(incomingFrame.intersects(existingAFrame))
        XCTAssertFalse(incomingFrame.intersects(existingBFrame))
    }

    func testIncrementalRefreshAssignsDistinctDefaultSlotsForNewGroups() {
        let suiteName = "WorkspaceMapViewModelDeterminismTests.incremental-default-slots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let groupA = makeTerminalGroup(idToken: "60000000-0000-0000-0000-000000000001")
        let groupB = makeTerminalGroup(idToken: "60000000-0000-0000-0000-000000000002")
        var sourceGroups: [WorkspaceMapGroupSnapshot] = [groupA]

        let model = WorkspaceMapViewModel(
            projectionSource: { WorkspaceMapSnapshot(groups: sourceGroups) },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            )
        )

        model.refresh()
        sourceGroups = [groupA, groupB]
        model.refresh()

        let layoutByID = Dictionary(uniqueKeysWithValues: model.layout.groups.map { ($0.id, $0) })
        guard let layoutA = layoutByID[groupA.id], let layoutB = layoutByID[groupB.id] else {
            XCTFail("Expected both incremental groups to exist in layout")
            return
        }

        let frameA = CGRect(
            x: layoutA.centerX - 880 / 2,
            y: layoutA.centerY - 560 / 2,
            width: 880,
            height: 560
        )
        let frameB = CGRect(
            x: layoutB.centerX - 880 / 2,
            y: layoutB.centerY - 560 / 2,
            width: 880,
            height: 560
        )

        XCTAssertFalse(
            frameA.intersects(frameB),
            "Incremental refresh must not assign overlapping default slots to newly appended groups."
        )
    }

    func testRuntimePathProducesPassingPerWorkloadArtifacts() async {
        var sequence = 0
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let suiteName = "WorkspaceMapViewModelDeterminismTests.workload-artifacts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = WorkspaceMapViewModel(
            projectionSource: {
                sequence += 1
                return self.makeLargeASnapshot(sequence: sequence)
            },
            commandExecutor: { request in
                WorkspaceMapCommandResult(
                    status: .executed,
                    message: "executed \(request.command.rawValue)"
                )
            },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: defaults,
                storageKey: UUID().uuidString
            ),
            nowProvider: { currentTime }
        )

        let focusTarget = WorkspaceMapEntityID("terminal-group:00000000-0000-0000-0000-000000000001")

        // Phase A: establish Large-A samples.
        for index in 0..<12 {
            currentTime = currentTime.addingTimeInterval(0.6)
            model.refresh()
            if index < 6 {
                currentTime = currentTime.addingTimeInterval(0.2)
                model.execute(.focusTopLevelGroup, targetID: focusTarget)
            }
        }

        // Phase B: produce burst-refresh requests while coalescing refresh execution.
        for _ in 0..<3 {
            for _ in 0..<80 {
                currentTime = currentTime.addingTimeInterval(0.04)
                model.scheduleRefresh()
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            currentTime = currentTime.addingTimeInterval(0.3)
            model.execute(.focusTopLevelGroup, targetID: focusTarget)
        }

        // Phase C: reset burst windows, then produce command burst for Large-C.
        currentTime = currentTime.addingTimeInterval(11.0)
        model.refresh()
        for _ in 0..<12 {
            currentTime = currentTime.addingTimeInterval(0.25)
            model.execute(.focusTopLevelGroup, targetID: focusTarget)
        }
        currentTime = currentTime.addingTimeInterval(0.2)
        model.refresh()

        let byWorkload = Dictionary(
            uniqueKeysWithValues: model.performance.workloadResults.map { ($0.workload, $0) }
        )

        for workload in WorkspaceMapPerformanceWorkload.allCases {
            let result = byWorkload[workload]
            XCTAssertNotNil(result)
            XCTAssertNotNil(result?.observed, "Expected observed metrics for \(workload.displayName)")
            XCTAssertEqual(result?.status, .pass, "Expected \(workload.displayName) to pass")
            XCTAssertFalse(
                result?.violations.contains("missing_artifact_data") ?? true,
                "Expected non-missing artifact data for \(workload.displayName)"
            )
        }
    }

    func testRuntimeRefreshMovesProjectionOffMainActorAndCoalescesInFlightRequests() async {
        final class ProjectionProbe: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var projectionCount = 0
            private(set) var projectionMainThreadFlags: [Bool] = []

            func recordProjection(isMainThread: Bool) {
                lock.lock()
                projectionCount += 1
                projectionMainThreadFlags.append(isMainThread)
                lock.unlock()
            }
        }

        let probe = ProjectionProbe()
        var captureCount = 0
        var cancellables: Set<AnyCancellable> = []
        var publishedGroupIDs: [WorkspaceMapEntityID] = []
        let model = WorkspaceMapViewModel(
            runtimeStateSource: {
                captureCount += 1
                return self.makeRuntimeState(sequence: captureCount)
            },
            backgroundProjector: { runtimeState, now in
                probe.recordProjection(isMainThread: Thread.isMainThread)
                Thread.sleep(forTimeInterval: 0.08)
                return WorkspaceMapProjectionService.makeSnapshot(from: runtimeState, now: now)
            },
            commandExecutor: { _ in WorkspaceMapCommandResult(status: .executed, message: "ok") },
            layoutStore: WorkspaceMapLayoutStore(
                defaults: UserDefaults(suiteName: "WorkspaceMapViewModelDeterminismTests.async-refresh")!,
                storageKey: UUID().uuidString
            )
        )

        model.$snapshot
            .dropFirst()
            .compactMap { $0.groups.first?.id }
            .sink { publishedGroupIDs.append($0) }
            .store(in: &cancellables)

        let firstTask = model.refresh()
        for _ in 0..<20 {
            _ = model.refresh()
        }

        await firstTask?.value
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(probe.projectionCount, 2)
        XCTAssertEqual(probe.projectionMainThreadFlags, [false, false])
        XCTAssertEqual(
            publishedGroupIDs,
            [WorkspaceMapEntityID("terminal-group:00000000-0000-0000-0000-000000000002")]
        )
        XCTAssertEqual(
            model.snapshot.groups.first?.id,
            WorkspaceMapEntityID("terminal-group:00000000-0000-0000-0000-000000000002")
        )
    }

    private func makeTerminalGroup(idToken: String) -> WorkspaceMapGroupSnapshot {
        WorkspaceMapGroupSnapshot(
            id: WorkspaceMapEntityID("terminal-group:\(idToken)"),
            kind: .terminal,
            title: "Terminal",
            isFocused: false,
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

    private func makeBrowserGroup(idToken: String) -> WorkspaceMapGroupSnapshot {
        WorkspaceMapGroupSnapshot(
            id: WorkspaceMapEntityID("browser-group:\(idToken)"),
            kind: .browser,
            title: "Browser",
            isFocused: false,
            terminal: nil,
            browser: WorkspaceMapBrowserGroupSnapshot(
                selectedPageID: "page-\(idToken)",
                displayedURL: "https://example.com/\(idToken)"
            )
        )
    }

    private func baseSize(for kind: WorkspaceMapGroupKind) -> CGSize {
        switch kind {
        case .terminal:
            return CGSize(width: 880, height: 560)
        case .browser:
            return CGSize(width: 980, height: 680)
        }
    }

    private func gapBetween(_ lhs: CGRect, _ rhs: CGRect) -> (CGFloat, CGFloat) {
        let xGap = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let yGap = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        return (xGap, yGap)
    }

    private func makeLargeASnapshot(sequence: Int) -> WorkspaceMapSnapshot {
        let terminalGroups: [WorkspaceMapGroupSnapshot] = (1...12).map { index in
            let terminalID = String(format: "%012d", index)
            return WorkspaceMapGroupSnapshot(
                id: WorkspaceMapEntityID("terminal-group:00000000-0000-0000-0000-\(terminalID)"),
                kind: .terminal,
                title: "Terminal \(index) #\(sequence)",
                isFocused: index == 1,
                terminal: WorkspaceMapTerminalGroupSnapshot(
                    rootNodeID: nil,
                    splitCount: 9,
                    paneCount: 10,
                    tabCount: 30,
                    nodes: []
                ),
                browser: nil
            )
        }

        let browserGroups: [WorkspaceMapGroupSnapshot] = (1...8).map { index in
            let browserID = String(format: "%012d", index)
            return WorkspaceMapGroupSnapshot(
                id: WorkspaceMapEntityID("browser-group:browser-\(browserID)"),
                kind: .browser,
                title: "Browser \(index) #\(sequence)",
                isFocused: false,
                terminal: nil,
                browser: WorkspaceMapBrowserGroupSnapshot(
                    selectedPageID: "page-\(index)-\(sequence)",
                    displayedURL: "https://example\(index).com/\(sequence)"
                )
            )
        }

        return WorkspaceMapSnapshot(
            generatedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
            groups: terminalGroups + browserGroups
        )
    }

    private func makeRuntimeState(sequence: Int) -> WorkspaceMapRuntimeState {
        let idToken = String(format: "%012d", sequence)
        return WorkspaceMapRuntimeState(
            captureSequence: UInt64(sequence),
            terminalGroups: [
                WorkspaceMapRuntimeTerminalGroup(
                    workspaceID: UUID(uuidString: "00000000-0000-0000-0000-\(idToken)")!,
                    title: "Terminal \(sequence)",
                    isFocused: sequence == 1,
                    root: .pane(
                        WorkspaceMapRuntimePane(
                            id: UUID(uuidString: "10000000-0000-0000-0000-\(idToken)")!,
                            isFocused: true,
                            tabs: [
                                WorkspaceMapRuntimePaneTab(
                                    id: UUID(uuidString: "20000000-0000-0000-0000-\(idToken)")!,
                                    title: "Tab \(sequence)",
                                    isActive: true
                                )
                            ]
                        )
                    )
                )
            ],
            browserGroups: []
        )
    }
}
