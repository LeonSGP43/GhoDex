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
    private let tickInterval: TimeInterval
    private let logger: Logger

    private var timer: Timer?

    init(
        bundleID: String,
        sampleStore: ControlHarnessSampleStore,
        policy: ControlHarnessSamplingPolicy = .default,
        tickInterval: TimeInterval = 0.125,
        inventoryProvider: @escaping @MainActor () -> [ControlHarnessSamplerTarget]
    ) {
        self.sampleStore = sampleStore
        self.policy = policy
        self.inventoryProvider = inventoryProvider
        self.tickInterval = tickInterval
        self.logger = Logger(subsystem: bundleID, category: "ControlHarnessReadSampler")
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllNow()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        refreshAllNow()
        logger.debug("control harness read sampler started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAllNow(now: Date = Date()) {
        for target in inventoryProvider() {
            refreshIfDue(target: target, scope: "visible", now: now)
            refreshIfDue(target: target, scope: "screen", now: now)
        }
    }

    @discardableResult
    func captureFreshSample(
        for terminalID: String,
        scope: String,
        surface: any ControlHarnessReadableSurface,
        activityClass: ControlHarnessSamplingActivityClass,
        now: Date = Date()
    ) -> ControlHarnessTerminalSample {
        let read: (content: String, cacheAgeMs: Int)
        switch scope {
        case "visible":
            read = surface.controlHarnessReadVisibleText(refresh: true)
        case "screen":
            read = surface.controlHarnessReadScreenText(refresh: true)
        default:
            read = ("", 0)
        }

        return sampleStore.store(
            terminalID: terminalID,
            scope: scope,
            content: read.content,
            consistency: "sampled_\(scope)",
            cacheAgeMs: read.cacheAgeMs,
            capturedAt: now,
            activityClass: activityClass,
            forcedFresh: true
        )
    }

    private func refreshIfDue(
        target: ControlHarnessSamplerTarget,
        scope: String,
        now: Date
    ) {
        let interval = policy.interval(for: scope, activityClass: target.activityClass)
        guard sampleStore.isDue(
            terminalID: target.terminalID,
            scope: scope,
            interval: interval,
            now: now
        ) else {
            return
        }

        _ = captureFreshSample(
            for: target.terminalID,
            scope: scope,
            surface: target.surface,
            activityClass: target.activityClass,
            now: now
        )
    }
}
