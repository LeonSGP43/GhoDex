import Foundation

enum WorkspaceMapPerformancePolicy {
    static func evaluate(
        metrics: WorkspaceMapPerformanceMetrics,
        for workload: WorkspaceMapPerformanceWorkload
    ) -> WorkspaceMapPerformanceWorkloadResult {
        let threshold = WorkspaceMapPerformanceBudget.threshold(for: workload)
        var violations: [String] = []

        if metrics.snapshotBuildP95MS > threshold.snapshotBuildP95MS {
            violations.append("snapshot_p95>\(threshold.snapshotBuildP95MS)")
        }
        if metrics.snapshotBuildP99MS > threshold.snapshotBuildP99MS {
            violations.append("snapshot_p99>\(threshold.snapshotBuildP99MS)")
        }
        if metrics.publishCadencePerSecond > threshold.publishCadenceMaxPerSecond {
            violations.append("publish_cadence>\(threshold.publishCadenceMaxPerSecond)")
        }
        if metrics.mainThreadSpikeCount > threshold.mainThreadSpikeMaxCount {
            violations.append("main_thread_spikes>\(threshold.mainThreadSpikeMaxCount)")
        }
        if metrics.commandLatencyP95MS > threshold.commandLatencyP95MS {
            violations.append("command_p95>\(threshold.commandLatencyP95MS)")
        }
        if metrics.commandFailureRate > threshold.commandFailureRateMax {
            violations.append("command_failure_rate>\(threshold.commandFailureRateMax)")
        }

        return WorkspaceMapPerformanceWorkloadResult(
            workload: workload,
            status: violations.isEmpty ? .pass : .fail,
            threshold: threshold,
            observed: metrics,
            violations: violations
        )
    }

    static func evaluateAll(metrics: WorkspaceMapPerformanceMetrics) -> [WorkspaceMapPerformanceWorkloadResult] {
        WorkspaceMapPerformanceWorkload.allCases.map { evaluate(metrics: metrics, for: $0) }
    }

    static func overallStatus(for results: [WorkspaceMapPerformanceWorkloadResult]) -> WorkspaceMapPerformanceGateStatus {
        results.allSatisfy { $0.status == .pass } ? .pass : .fail
    }
}

struct WorkspaceMapPercentile {
    static func p95(_ values: [Double]) -> Double {
        percentile(values, p: 0.95)
    }

    static func p99(_ values: [Double]) -> Double {
        percentile(values, p: 0.99)
    }

    static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * clamped).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}

struct WorkspaceMapPerformanceRecorder {
    private let maxSamples: Int
    private(set) var snapshotBuildMS: [Double] = []
    private(set) var commandLatencyMS: [Double] = []
    private(set) var commandStatuses: [WorkspaceMapCommandStatus] = []
    private(set) var publishTimestamps: [Date] = []
    private(set) var workloadSnapshotBuildMS: [WorkspaceMapPerformanceWorkload: [Double]] = [:]
    private(set) var workloadCommandLatencyMS: [WorkspaceMapPerformanceWorkload: [Double]] = [:]
    private(set) var workloadCommandStatuses: [WorkspaceMapPerformanceWorkload: [WorkspaceMapCommandStatus]] = [:]
    private(set) var workloadPublishTimestamps: [WorkspaceMapPerformanceWorkload: [Date]] = [:]

    init(maxSamples: Int = 120) {
        self.maxSamples = max(20, maxSamples)
    }

    mutating func recordSnapshotBuild(ms: Double, workload: WorkspaceMapPerformanceWorkload? = nil) {
        snapshotBuildMS.append(ms)
        trim(&snapshotBuildMS)
        if let workload {
            var values = workloadSnapshotBuildMS[workload, default: []]
            values.append(ms)
            trim(&values)
            workloadSnapshotBuildMS[workload] = values
        }
    }

    mutating func recordCommandLatency(ms: Double, workload: WorkspaceMapPerformanceWorkload? = nil) {
        commandLatencyMS.append(ms)
        trim(&commandLatencyMS)
        if let workload {
            var values = workloadCommandLatencyMS[workload, default: []]
            values.append(ms)
            trim(&values)
            workloadCommandLatencyMS[workload] = values
        }
    }

    mutating func recordCommandStatus(
        _ status: WorkspaceMapCommandStatus,
        workload: WorkspaceMapPerformanceWorkload? = nil
    ) {
        commandStatuses.append(status)
        trim(&commandStatuses)
        if let workload {
            var values = workloadCommandStatuses[workload, default: []]
            values.append(status)
            trim(&values)
            workloadCommandStatuses[workload] = values
        }
    }

    mutating func recordPublish(at date: Date, workload: WorkspaceMapPerformanceWorkload? = nil) {
        publishTimestamps.append(date)
        trim(&publishTimestamps)
        if let workload {
            var values = workloadPublishTimestamps[workload, default: []]
            values.append(date)
            trim(&values)
            workloadPublishTimestamps[workload] = values
        }
    }

    func snapshot() -> WorkspaceMapPerformanceSnapshot {
        let metrics = buildMetrics(
            snapshotSamples: snapshotBuildMS,
            commandSamples: commandLatencyMS,
            commandStatusSamples: commandStatuses,
            publishSamples: publishTimestamps
        )
        let workloadResults = WorkspaceMapPerformanceWorkload.allCases.map(evaluateWorkload(_:))
        return WorkspaceMapPerformanceSnapshot(
            metrics: metrics,
            gate: WorkspaceMapPerformancePolicy.overallStatus(for: workloadResults),
            workloadResults: workloadResults
        )
    }

    private func evaluateWorkload(_ workload: WorkspaceMapPerformanceWorkload) -> WorkspaceMapPerformanceWorkloadResult {
        guard let snapshotSamples = workloadSnapshotBuildMS[workload],
              let commandSamples = workloadCommandLatencyMS[workload],
              let commandStatusSamples = workloadCommandStatuses[workload],
              let publishSamples = workloadPublishTimestamps[workload],
              hasRequiredSamples(
                snapshotSamples: snapshotSamples,
                commandSamples: commandSamples,
                commandStatusSamples: commandStatusSamples,
                publishSamples: publishSamples
              ) else {
            return WorkspaceMapPerformanceWorkloadResult(
                workload: workload,
                status: .fail,
                threshold: WorkspaceMapPerformanceBudget.threshold(for: workload),
                observed: nil,
                violations: ["missing_artifact_data"]
            )
        }

        return WorkspaceMapPerformancePolicy.evaluate(
            metrics: buildMetrics(
                snapshotSamples: snapshotSamples,
                commandSamples: commandSamples,
                commandStatusSamples: commandStatusSamples,
                publishSamples: publishSamples
            ),
            for: workload
        )
    }

    private func hasRequiredSamples(
        snapshotSamples: [Double],
        commandSamples: [Double],
        commandStatusSamples: [WorkspaceMapCommandStatus],
        publishSamples: [Date]
    ) -> Bool {
        !snapshotSamples.isEmpty &&
            !commandSamples.isEmpty &&
            !commandStatusSamples.isEmpty &&
            publishSamples.count > 1
    }

    private func buildMetrics(
        snapshotSamples: [Double],
        commandSamples: [Double],
        commandStatusSamples: [WorkspaceMapCommandStatus],
        publishSamples: [Date]
    ) -> WorkspaceMapPerformanceMetrics {
        WorkspaceMapPerformanceMetrics(
            snapshotBuildP95MS: WorkspaceMapPercentile.p95(snapshotSamples),
            snapshotBuildP99MS: WorkspaceMapPercentile.p99(snapshotSamples),
            commandLatencyP95MS: WorkspaceMapPercentile.p95(commandSamples),
            publishCadencePerSecond: publishCadencePerSecond(for: publishSamples),
            mainThreadSpikeCount: mainThreadSpikeCount(
                snapshotSamples: snapshotSamples,
                commandSamples: commandSamples
            ),
            commandFailureRate: commandFailureRate(commandStatusSamples)
        )
    }

    private func publishCadencePerSecond(for timestamps: [Date]) -> Double {
        guard timestamps.count > 1,
              let first = timestamps.first,
              let last = timestamps.last else {
            return 0
        }

        let span = max(last.timeIntervalSince(first), 0.001)
        return Double(timestamps.count - 1) / span
    }

    private func mainThreadSpikeCount(snapshotSamples: [Double], commandSamples: [Double]) -> Int {
        let spikeThreshold = WorkspaceMapPerformanceBudget.mainThreadSpikeThresholdMS
        let snapshotSpikes = snapshotSamples.filter { $0 > spikeThreshold }.count
        let commandSpikes = commandSamples.filter { $0 > spikeThreshold }.count
        return snapshotSpikes + commandSpikes
    }

    private func commandFailureRate(_ statuses: [WorkspaceMapCommandStatus]) -> Double {
        guard !statuses.isEmpty else { return 0 }
        let failures = statuses.filter { $0 != .executed }.count
        return Double(failures) / Double(statuses.count)
    }

    private func trim<T>(_ values: inout [T]) {
        let overflow = values.count - maxSamples
        if overflow > 0 {
            values.removeFirst(overflow)
        }
    }
}
