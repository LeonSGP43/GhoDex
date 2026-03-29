import XCTest
import Foundation
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
