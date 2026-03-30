import Foundation
import OSLog

struct ControlHarnessSamplerTarget {
    let terminalID: String
    let surface: any ControlHarnessReadableSurface
    let activityClass: ControlHarnessSamplingActivityClass
}

struct ControlHarnessSamplingPolicy {
    let managedActiveVisibleInterval: TimeInterval
    let managedActiveScreenInterval: TimeInterval
    let observedVisibleInterval: TimeInterval
    let observedScreenInterval: TimeInterval
    let backgroundVisibleInterval: TimeInterval
    let backgroundScreenInterval: TimeInterval

    static let `default` = ControlHarnessSamplingPolicy(
        managedActiveVisibleInterval: 0.125,
        managedActiveScreenInterval: 0.4,
        observedVisibleInterval: 0.6,
        observedScreenInterval: 1.0,
        backgroundVisibleInterval: 2.5,
        backgroundScreenInterval: 5.0
    )

    func interval(
        for scope: String,
        activityClass: ControlHarnessSamplingActivityClass
    ) -> TimeInterval {
        switch (activityClass, scope) {
        case (.managedActive, "visible"):
            managedActiveVisibleInterval
        case (.managedActive, "screen"):
            managedActiveScreenInterval
        case (.observed, "visible"):
            observedVisibleInterval
        case (.observed, "screen"):
            observedScreenInterval
        case (.background, "visible"):
            backgroundVisibleInterval
        case (.background, "screen"):
            backgroundScreenInterval
        default:
            observedScreenInterval
        }
    }
}

@MainActor
final class ControlHarnessReadSampler {
    private let sampleStore: ControlHarnessSampleStore
    private let policy: ControlHarnessSamplingPolicy
    private let inventoryProvider: @MainActor () -> [ControlHarnessSamplerTarget]
    private let performanceMonitor: ControlHarnessPerformanceMonitor?
    private let managedActiveTickInterval: TimeInterval
    private let observedTickInterval: TimeInterval
    private let backgroundTickInterval: TimeInterval
    private let logger: Logger

    private var timer: Timer?
    private var currentTickInterval: TimeInterval?

    init(
        bundleID: String,
        sampleStore: ControlHarnessSampleStore,
        policy: ControlHarnessSamplingPolicy = .default,
        tickInterval: TimeInterval = 0.125,
        observedTickInterval: TimeInterval = 0.5,
        backgroundTickInterval: TimeInterval = 1.5,
        performanceMonitor: ControlHarnessPerformanceMonitor? = nil,
        inventoryProvider: @escaping @MainActor () -> [ControlHarnessSamplerTarget]
    ) {
        self.sampleStore = sampleStore
        self.policy = policy
        self.inventoryProvider = inventoryProvider
        self.performanceMonitor = performanceMonitor
        self.managedActiveTickInterval = max(0.05, tickInterval)
        self.observedTickInterval = max(self.managedActiveTickInterval, observedTickInterval)
        self.backgroundTickInterval = max(self.observedTickInterval, backgroundTickInterval)
        self.logger = Logger(subsystem: bundleID, category: "ControlHarnessReadSampler")
    }

    func start() {
        guard timer == nil else { return }
        scheduleTimer(interval: managedActiveTickInterval)
        refreshAllNow()
        logger.debug("control harness read sampler started")
        RuntimeDiagnosticsLogger.log(
            component: "control_harness.read_sampler",
            event: "start",
            details: [
                "managed_active_tick_seconds": String(format: "%.3f", managedActiveTickInterval),
                "observed_tick_seconds": String(format: "%.3f", observedTickInterval),
                "background_tick_seconds": String(format: "%.3f", backgroundTickInterval),
            ]
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentTickInterval = nil
        RuntimeDiagnosticsLogger.log(
            component: "control_harness.read_sampler",
            event: "stop"
        )
    }

    func refreshAllNow(now: Date = Date()) {
        let started = DispatchTime.now()
        let targets = inventoryProvider()
        reconfigureTimerIfNeeded(for: targets)
        var refreshedCount = 0

        for target in targets {
            if refreshIfDue(target: target, scope: "visible", now: now) {
                refreshedCount += 1
            }
            if refreshIfDue(target: target, scope: "screen", now: now) {
                refreshedCount += 1
            }
        }

        performanceMonitor?.recordSamplerTick(
            targetCount: targets.count,
            refreshedCount: refreshedCount,
            durationMs: Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000,
            at: now
        )
    }

    @discardableResult
    func captureFreshSample(
        for terminalID: String,
        scope: String,
        surface: any ControlHarnessReadableSurface,
        activityClass: ControlHarnessSamplingActivityClass,
        now: Date = Date()
    ) -> ControlHarnessTerminalSample {
        let started = DispatchTime.now()
        let read: (content: String, cacheAgeMs: Int)
        switch scope {
        case "visible":
            // Avoid forcing a full terminal dump on every sampler tick.
            // Cached reads still refresh automatically when the cache expires.
            read = surface.controlHarnessReadVisibleText(refresh: false)
        case "screen":
            read = surface.controlHarnessReadScreenText(refresh: false)
        default:
            read = ("", 0)
        }

        let sample = sampleStore.store(
            terminalID: terminalID,
            scope: scope,
            content: read.content,
            consistency: "sampled_\(scope)",
            cacheAgeMs: read.cacheAgeMs,
            capturedAt: now,
            activityClass: activityClass,
            forcedFresh: true
        )

        performanceMonitor?.recordSamplerCapture(
            scope: scope,
            activityClass: activityClass,
            durationMs: Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000,
            at: now
        )

        return sample
    }

    private func desiredTickInterval(for targets: [ControlHarnessSamplerTarget]) -> TimeInterval {
        guard !targets.isEmpty else {
            return backgroundTickInterval
        }
        if targets.contains(where: { $0.activityClass == .managedActive }) {
            return managedActiveTickInterval
        }
        if targets.contains(where: { $0.activityClass == .observed }) {
            return observedTickInterval
        }
        return backgroundTickInterval
    }

    private func reconfigureTimerIfNeeded(for targets: [ControlHarnessSamplerTarget]) {
        let desired = desiredTickInterval(for: targets)
        guard currentTickInterval == nil || abs((currentTickInterval ?? 0) - desired) > 0.001 else {
            return
        }
        scheduleTimer(interval: desired)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllNow()
            }
        }
        timer.tolerance = min(max(interval * 0.2, 0.02), 0.5)
        self.timer = timer
        currentTickInterval = interval
        RunLoop.main.add(timer, forMode: .common)
        RuntimeDiagnosticsLogger.log(
            component: "control_harness.read_sampler",
            event: "schedule_timer",
            details: [
                "interval_seconds": String(format: "%.3f", interval),
            ]
        )
    }

    private func refreshIfDue(
        target: ControlHarnessSamplerTarget,
        scope: String,
        now: Date
    ) -> Bool {
        let interval = policy.interval(for: scope, activityClass: target.activityClass)
        guard sampleStore.isDue(
            terminalID: target.terminalID,
            scope: scope,
            interval: interval,
            now: now
        ) else {
            return false
        }

        _ = captureFreshSample(
            for: target.terminalID,
            scope: scope,
            surface: target.surface,
            activityClass: target.activityClass,
            now: now
        )

        return true
    }
}
