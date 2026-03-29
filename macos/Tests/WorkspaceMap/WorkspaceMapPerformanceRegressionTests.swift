import XCTest
@testable import GhoDex

@MainActor
final class WorkspaceMapPerformanceRegressionTests: XCTestCase {
    func testLargeAFixtureProjectionP95WithinBudget() {
        let runtime = makeLargeARuntimeState()
        var samples: [Double] = []

        for _ in 0..<120 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = WorkspaceMapProjectionService.makeSnapshot(
                from: runtime,
                now: Date(timeIntervalSince1970: 1)
            )
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }

        let p95 = WorkspaceMapPercentile.p95(samples)
        XCTAssertLessThanOrEqual(p95, WorkspaceMapPerformanceBudget.largeASnapshotBuildP95MS)
    }

    func testProjectionScalingIsSubQuadraticAcrossPaneSizes() {
        let t30 = meanProjectionMS(totalPanes: 30)
        let t60 = meanProjectionMS(totalPanes: 60)
        let t120 = meanProjectionMS(totalPanes: 120)

        // 30 -> 120 panes is 4x input size; quadratic growth would be 16x.
        XCTAssertLessThan(t120 / max(t30, 0.001), 8.0)
        XCTAssertLessThan(t60 / max(t30, 0.001), 4.0)
    }

    private func meanProjectionMS(totalPanes: Int) -> Double {
        let runtime = makeRuntimeState(
            terminalGroupCount: 6,
            browserGroupCount: 4,
            panesPerTerminal: max(1, totalPanes / 6),
            tabsPerPane: 3
        )
        var samples: [Double] = []

        for _ in 0..<80 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = WorkspaceMapProjectionService.makeSnapshot(
                from: runtime,
                now: Date(timeIntervalSince1970: 2)
            )
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }

        return samples.reduce(0, +) / Double(samples.count)
    }

    private func makeLargeARuntimeState() -> WorkspaceMapRuntimeState {
        makeRuntimeState(
            terminalGroupCount: 12,
            browserGroupCount: 8,
            panesPerTerminal: 10,
            tabsPerPane: 3
        )
    }

    private func makeRuntimeState(
        terminalGroupCount: Int,
        browserGroupCount: Int,
        panesPerTerminal: Int,
        tabsPerPane: Int
    ) -> WorkspaceMapRuntimeState {
        let terminals = (0..<terminalGroupCount).map { groupIndex in
            let panes = (0..<panesPerTerminal).map { paneIndex in
                let paneID = uuid(groupIndex, paneIndex, 0, seed: 9000)
                let tabs = (0..<tabsPerPane).map { tabIndex in
                    WorkspaceMapRuntimePaneTab(
                        id: uuid(groupIndex, paneIndex, tabIndex, seed: 7000),
                        title: "T\(groupIndex)-P\(paneIndex)-Tab\(tabIndex)",
                        isActive: tabIndex == 0
                    )
                }
                return WorkspaceMapRuntimePane(
                    id: paneID,
                    isFocused: groupIndex == 0 && paneIndex == 0,
                    tabs: tabs
                )
            }

            return WorkspaceMapRuntimeTerminalGroup(
                workspaceID: uuid(groupIndex, 0, 0, seed: 3000),
                title: "Terminal \(groupIndex)",
                isFocused: groupIndex == 0,
                root: buildBalancedSplitTree(panes: panes, depth: 0)
            )
        }

        let browsers = (0..<browserGroupCount).map { index in
            WorkspaceMapRuntimeBrowserGroup(
                workspaceID: uuid(index, 0, 0, seed: 5000),
                title: "Browser \(index)",
                isFocused: false,
                selectedPageID: uuid(index, 0, 0, seed: 6000).uuidString.lowercased(),
                displayedURL: "https://example\(index).com"
            )
        }

        return WorkspaceMapRuntimeState(
            terminalGroups: terminals,
            browserGroups: browsers
        )
    }

    private func buildBalancedSplitTree(
        panes: [WorkspaceMapRuntimePane],
        depth: Int
    ) -> WorkspaceMapRuntimeTerminalNode? {
        guard !panes.isEmpty else { return nil }
        if panes.count == 1 {
            return .pane(panes[0])
        }

        let mid = panes.count / 2
        guard let left = buildBalancedSplitTree(panes: Array(panes[..<mid]), depth: depth + 1),
              let right = buildBalancedSplitTree(panes: Array(panes[mid...]), depth: depth + 1) else {
            return nil
        }

        return .split(
            direction: depth.isMultiple(of: 2) ? .horizontal : .vertical,
            ratio: 0.5,
            left: left,
            right: right
        )
    }

    private func uuid(_ a: Int, _ b: Int, _ c: Int, seed: Int) -> UUID {
        var hash = seed &* 1_000_003
        hash = hash &* 31 &+ a
        hash = hash &* 31 &+ b
        hash = hash &* 31 &+ c
        let raw = UInt64(bitPattern: Int64(hash))
        let suffix = String(format: "%012llx", raw & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }
}
