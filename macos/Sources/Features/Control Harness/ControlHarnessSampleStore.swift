import Foundation

@MainActor
protocol ControlHarnessReadableSurface: AnyObject {
    var id: UUID { get }
    func controlHarnessReadVisibleText(refresh: Bool) -> (content: String, cacheAgeMs: Int)
    func controlHarnessReadScreenText(refresh: Bool) -> (content: String, cacheAgeMs: Int)
}

extension Ghostty.SurfaceView: ControlHarnessReadableSurface {
    func controlHarnessReadVisibleText(refresh: Bool) -> (content: String, cacheAgeMs: Int) {
        controlHarnessVisibleText(refresh: refresh)
    }

    func controlHarnessReadScreenText(refresh: Bool) -> (content: String, cacheAgeMs: Int) {
        controlHarnessScreenText(refresh: refresh)
    }
}

enum ControlHarnessSamplingActivityClass: String, Sendable {
    case managedActive = "managed_active"
    case observed
    case background

    func maxSampleAge(for scope: String) -> TimeInterval {
        switch (self, scope) {
        case (.managedActive, "visible"):
            0.125
        case (.managedActive, "screen"):
            0.4
        case (.observed, "visible"):
            0.6
        case (.observed, "screen"):
            1.0
        case (.background, "visible"):
            2.5
        case (.background, "screen"):
            5.0
        default:
            1.0
        }
    }

    init(managedState: AITerminalManagedState, isFocused: Bool, isVisible: Bool) {
        switch managedState {
        case .manual, .managedPaused, .managedCompleted, .managedFailed:
            self = .background
        case .managedActive:
            if isFocused {
                self = .managedActive
            } else if isVisible {
                self = .observed
            } else {
                self = .background
            }
        case .observed, .managedWaitingApproval:
            self = (isFocused || isVisible) ? .observed : .background
        }
    }
}

struct ControlHarnessTerminalSample {
    let terminalID: String
    let scope: String
    let content: String
    let consistency: String
    let cacheAgeMs: Int
    let capturedAt: Date
    let activityClass: ControlHarnessSamplingActivityClass
    let forcedFresh: Bool
}

@MainActor
final class ControlHarnessSampleStore {
    private struct SampleKey: Hashable {
        let terminalID: String
        let scope: String
    }

    private var samples: [SampleKey: ControlHarnessTerminalSample] = [:]

    func sample(for terminalID: String, scope: String) -> ControlHarnessTerminalSample? {
        samples[.init(terminalID: terminalID, scope: scope)]
    }

    func store(
        terminalID: String,
        scope: String,
        content: String,
        consistency: String,
        cacheAgeMs: Int,
        capturedAt: Date,
        activityClass: ControlHarnessSamplingActivityClass,
        forcedFresh: Bool
    ) -> ControlHarnessTerminalSample {
        let sample = ControlHarnessTerminalSample(
            terminalID: terminalID,
            scope: scope,
            content: content,
            consistency: consistency,
            cacheAgeMs: cacheAgeMs,
            capturedAt: capturedAt,
            activityClass: activityClass,
            forcedFresh: forcedFresh
        )
        samples[.init(terminalID: terminalID, scope: scope)] = sample
        return sample
    }

    func isDue(
        terminalID: String,
        scope: String,
        interval: TimeInterval,
        now: Date
    ) -> Bool {
        guard let sample = sample(for: terminalID, scope: scope) else {
            return true
        }

        return now.timeIntervalSince(sample.capturedAt) >= interval
    }

    func isFresh(
        _ sample: ControlHarnessTerminalSample,
        activityClass: ControlHarnessSamplingActivityClass,
        now: Date
    ) -> Bool {
        now.timeIntervalSince(sample.capturedAt) < activityClass.maxSampleAge(for: sample.scope)
    }

    func removeTerminal(_ terminalID: String) {
        samples.keys
            .filter { $0.terminalID == terminalID }
            .forEach { samples.removeValue(forKey: $0) }
    }
}
