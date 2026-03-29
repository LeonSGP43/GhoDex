import XCTest
@testable import GhoDex

final class WorkspaceMapPerformancePolicyTests: XCTestCase {
    func testEvaluateAllWorkloadsPassWhenMetricsWithinThresholds() {
        let metrics = WorkspaceMapPerformanceMetrics(
            snapshotBuildP95MS: 18,
            snapshotBuildP99MS: 30,
            commandLatencyP95MS: 35,
            publishCadencePerSecond: 10,
            mainThreadSpikeCount: 1,
            commandFailureRate: 0
        )

        let results = WorkspaceMapPerformancePolicy.evaluateAll(metrics: metrics)
        XCTAssertEqual(results.count, WorkspaceMapPerformanceWorkload.allCases.count)
        XCTAssertTrue(results.allSatisfy { $0.status == .pass })
        XCTAssertEqual(WorkspaceMapPerformancePolicy.overallStatus(for: results), .pass)
    }

    func testEvaluateLargeBFailsWhenCadenceExceedsThreshold() {
        let metrics = WorkspaceMapPerformanceMetrics(
            snapshotBuildP95MS: 5,
            snapshotBuildP99MS: 8,
            commandLatencyP95MS: 7,
            publishCadencePerSecond: 21,
            mainThreadSpikeCount: 0,
            commandFailureRate: 0
        )

        let result = WorkspaceMapPerformancePolicy.evaluate(metrics: metrics, for: .largeB)
        XCTAssertEqual(result.status, .fail)
        XCTAssertTrue(result.violations.contains(where: { $0.hasPrefix("publish_cadence>") }))
    }

    func testRecorderSnapshotIncludesPerWorkloadStatuses() {
        var recorder = WorkspaceMapPerformanceRecorder(maxSamples: 80)
        let start = Date(timeIntervalSince1970: 10)

        for workload in WorkspaceMapPerformanceWorkload.allCases {
            for index in 0..<40 {
                recorder.recordSnapshotBuild(ms: 9, workload: workload)
                recorder.recordCommandLatency(ms: 11, workload: workload)
                recorder.recordCommandStatus(.executed, workload: workload)
                recorder.recordPublish(at: start.addingTimeInterval(Double(index) * 0.2), workload: workload)
            }
        }

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.workloadResults.count, WorkspaceMapPerformanceWorkload.allCases.count)
        XCTAssertTrue(snapshot.workloadResults.allSatisfy { $0.status == .pass })
        XCTAssertEqual(snapshot.commandFailureRate, 0)
        XCTAssertEqual(snapshot.mainThreadSpikeCount, 0)
        XCTAssertEqual(snapshot.gate, .pass)
    }

    func testRecorderGateFailsWhenCommandFailureRateIsNonZero() {
        var recorder = WorkspaceMapPerformanceRecorder(maxSamples: 40)
        let start = Date(timeIntervalSince1970: 100)

        for workload in WorkspaceMapPerformanceWorkload.allCases {
            for index in 0..<10 {
                recorder.recordSnapshotBuild(ms: 3, workload: workload)
                recorder.recordCommandLatency(ms: 4, workload: workload)
                recorder.recordCommandStatus(.executed, workload: workload)
                recorder.recordPublish(at: start.addingTimeInterval(Double(index) * 0.25), workload: workload)
            }
        }
        recorder.recordCommandStatus(.invalidRequest, workload: .largeC)

        let snapshot = recorder.snapshot()
        XCTAssertGreaterThan(snapshot.commandFailureRate, 0)
        XCTAssertEqual(snapshot.gate, .fail)
        XCTAssertEqual(snapshot.workloadResults.first(where: { $0.workload == .largeC })?.status, .fail)
        XCTAssertTrue(
            snapshot.workloadResults
                .filter { $0.workload != .largeC }
                .allSatisfy { $0.status == .pass }
        )
    }

    func testRecorderFailsClosedWhenWorkloadArtifactsAreMissing() {
        var recorder = WorkspaceMapPerformanceRecorder(maxSamples: 40)
        let start = Date(timeIntervalSince1970: 200)

        for index in 0..<20 {
            recorder.recordSnapshotBuild(ms: 5, workload: .largeA)
            recorder.recordCommandLatency(ms: 6, workload: .largeA)
            recorder.recordCommandStatus(.executed, workload: .largeA)
            recorder.recordPublish(at: start.addingTimeInterval(Double(index) * 0.2), workload: .largeA)
        }

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.gate, .fail)
        XCTAssertEqual(snapshot.workloadResults.first(where: { $0.workload == .largeA })?.status, .pass)

        let missingWorkloads = snapshot.workloadResults.filter { $0.workload != .largeA }
        XCTAssertTrue(missingWorkloads.allSatisfy { $0.status == .fail })
        XCTAssertTrue(
            missingWorkloads
                .flatMap(\.violations)
                .contains("missing_artifact_data")
        )
    }
}
