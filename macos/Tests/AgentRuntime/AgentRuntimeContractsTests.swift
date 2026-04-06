import Foundation
import Testing
@testable import GhoDex

struct AgentRuntimeContractsTests {
    @Test func taskStateTransitionsFollowV1Contract() {
        #expect(AgentRuntimeTaskState.queued.canTransition(to: .claimed))
        #expect(AgentRuntimeTaskState.claimed.canTransition(to: .running))
        #expect(AgentRuntimeTaskState.running.canTransition(to: .waitingApproval))
        #expect(AgentRuntimeTaskState.waitingApproval.canTransition(to: .paused))
        #expect(!AgentRuntimeTaskState.waitingApproval.canTransition(to: .running))
        #expect(AgentRuntimeTaskState.paused.canTransition(to: .running))
        #expect(AgentRuntimeTaskState.running.canTransition(to: .completed))
        #expect(!AgentRuntimeTaskState.completed.canTransition(to: .running))
        #expect(!AgentRuntimeTaskState.cancelled.canTransition(to: .queued))
    }

    @Test func settingsClampLeaseDurationIntoSafeRange() {
        let low = AgentRuntimeSettings(
            enabled: true,
            defaultLeaseDurationSeconds: 1,
            staleTaskPolicy: .requeueClaimedWork
        ).sanitized()
        let high = AgentRuntimeSettings(
            enabled: true,
            defaultLeaseDurationSeconds: 999,
            staleTaskPolicy: .pauseClaimedWork
        ).sanitized()

        #expect(low.defaultLeaseDurationSeconds == AgentRuntimeSettings.minimumLeaseDurationSeconds)
        #expect(high.defaultLeaseDurationSeconds == AgentRuntimeSettings.maximumLeaseDurationSeconds)
    }

    @Test func sessionNormalizesCapabilitiesAndDetectsLeaseExpiry() {
        let now = Date()
        var session = AgentRuntimeSession(
            clientKind: .codexTab,
            capabilities: ["terminal", " terminal ", "", "task-runtime", "browser", "vision", "terminal"],
            createdAt: now,
            updatedAt: now,
            leaseDurationSeconds: 30
        )
        session.renewLease(
            at: now,
            defaults: AgentRuntimeSettings(defaultLeaseDurationSeconds: 30)
        )

        #expect(session.capabilities == [
            AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
            AgentRuntimeCapability.runtimeExecutorTerminal.rawValue,
            AgentRuntimeCapability.runtimeExecutorVision.rawValue,
            AgentRuntimeCapability.runtimeTaskManage.rawValue,
        ])
        #expect(session.isLeaseExpired(at: now.addingTimeInterval(31)))
        #expect(!session.isLeaseExpired(at: now.addingTimeInterval(1)))
    }

    @Test func taskKindsExposeDefaultExecutorCapabilities() {
        #expect(AgentRuntimeTaskKind.terminalCommand.defaultCapabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorTerminal.rawValue,
        ])
        #expect(AgentRuntimeTaskKind.browserNavigation.defaultCapabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
        ])
        #expect(AgentRuntimeTaskKind.browserInteraction.defaultCapabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
        ])
        #expect(AgentRuntimeTaskKind.visionAutomation.defaultCapabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorVision.rawValue,
        ])
        #expect(AgentRuntimeTaskKind.hostWorkflow.defaultCapabilityRequirements.isEmpty)
    }

    @Test func scheduleTransitionsAndRecurrenceFollowV1Contract() {
        #expect(AgentRuntimeScheduleState.active.canTransition(to: .paused))
        #expect(AgentRuntimeScheduleState.paused.canTransition(to: .active))
        #expect(AgentRuntimeScheduleState.active.canTransition(to: .cancelled))
        #expect(!AgentRuntimeScheduleState.completed.canTransition(to: .active))

        let once = AgentRuntimeScheduleRecurrence(mode: .once, intervalSeconds: 5).sanitized()
        #expect(once.intervalSeconds == nil)

        let interval = AgentRuntimeScheduleRecurrence(mode: .interval, intervalSeconds: 0.1).sanitized()
        #expect(interval.intervalSeconds == AgentRuntimeScheduleRecurrence.minimumIntervalSeconds)
    }

    @Test func scheduleMaterializationAdvancesOnceAndIntervalSchedules() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var once = AgentRuntimeSchedule(
            taskKind: .terminalCommand,
            startAt: start,
            recurrence: .init(mode: .once),
            createdAt: start,
            updatedAt: start
        )
        once.markMaterialized(
            fireAt: start,
            materializedAt: start.addingTimeInterval(1),
            taskID: UUID()
        )
        #expect(once.state == .completed)
        #expect(once.nextRunAt == nil)

        var interval = AgentRuntimeSchedule(
            taskKind: .terminalCommand,
            startAt: start,
            recurrence: .init(mode: .interval, intervalSeconds: 30),
            createdAt: start,
            updatedAt: start
        )
        let taskID = UUID()
        interval.markMaterialized(
            fireAt: start,
            materializedAt: start.addingTimeInterval(5),
            taskID: taskID
        )
        #expect(interval.state == .active)
        #expect(interval.lastTaskID == taskID)
        #expect(interval.nextRunAt == start.addingTimeInterval(35))
    }

    @Test @MainActor func browserExecutionCoordinatorCompletesNavigationTasksViaNewTabProtocol() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .browserNavigation,
            payload: .init(metadata: ["url": "https://example.com"])
        )

        var capturedRequest: BrowserExternalCommandRequest?
        let coordinator = AgentRuntimeExecutionCoordinator(
            store: store,
            browserCommandRunner: { request in
                capturedRequest = request
                return .success(for: request, resultJSON: #"{"accepted":true}"#)
            }
        )

        await coordinator.drainBrowserTasksOnce()

        let completedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        let browserRequest = try #require(capturedRequest)
        let sessionID = try #require(completedTask.sessionID)
        let executorSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == sessionID }))

        #expect(completedTask.state == .completed)
        #expect(browserRequest.command == .newTab)
        #expect(browserRequest.payload["url"] == "https://example.com")
        #expect(executorSession.clientKind == .hostExecutor)
        #expect(executorSession.capabilities == [
            AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
        ])
    }

    @Test @MainActor func browserExecutionCoordinatorMapsTypeTextActionsToFrontmostBrowserTab() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .browserInteraction,
            payload: .init(
                text: "hello runtime",
                metadata: [
                    "action": "type_text",
                    "selector": "#prompt",
                ]
            )
        )

        var capturedRequest: BrowserExternalCommandRequest?
        let coordinator = AgentRuntimeExecutionCoordinator(
            store: store,
            browserCommandRunner: { request in
                capturedRequest = request
                return .success(for: request, resultJSON: #"{"accepted":true}"#)
            },
            defaultBrowserTabIDProvider: { "browser-tab-frontmost" }
        )

        await coordinator.drainBrowserTasksOnce()

        let completedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        let browserRequest = try #require(capturedRequest)

        #expect(completedTask.state == .completed)
        #expect(browserRequest.command == .typeText)
        #expect(browserRequest.browserTabID == "browser-tab-frontmost")
        #expect(browserRequest.payload["selector"] == "#prompt")
        #expect(browserRequest.payload["text"] == "hello runtime")
    }

    @Test @MainActor func browserExecutionCoordinatorUsesLoadURLForTargetedNavigation() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .browserNavigation,
            payload: .init(metadata: [
                "url": "https://example.com/docs",
                "browser_tab_id": "browser-tab-123",
            ])
        )

        var capturedRequest: BrowserExternalCommandRequest?
        let coordinator = AgentRuntimeExecutionCoordinator(
            store: store,
            browserCommandRunner: { request in
                capturedRequest = request
                return .success(for: request, resultJSON: #"{"accepted":true}"#)
            }
        )

        await coordinator.drainBrowserTasksOnce()

        let completedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        let browserRequest = try #require(capturedRequest)

        #expect(completedTask.state == .completed)
        #expect(browserRequest.command == .loadURL)
        #expect(browserRequest.browserTabID == "browser-tab-123")
        #expect(browserRequest.payload["url"] == "https://example.com/docs")
    }

    @Test @MainActor func browserExecutionCoordinatorMarksTaskFailedWhenBrowserExecutionFails() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .browserInteraction,
            payload: .init(metadata: [
                "action": "click",
                "selector": "#submit",
                "browser_tab_id": "browser-tab-123",
            ])
        )

        var capturedRequest: BrowserExternalCommandRequest?
        let coordinator = AgentRuntimeExecutionCoordinator(
            store: store,
            browserCommandRunner: { request in
                capturedRequest = request
                return .failure(
                    for: request,
                    error: .internalFailure("browser click failed")
                )
            }
        )

        await coordinator.drainBrowserTasksOnce()

        let failedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        let browserRequest = try #require(capturedRequest)

        #expect(browserRequest.command == .click)
        #expect(browserRequest.browserTabID == "browser-tab-123")
        #expect(failedTask.state == .failed)
        #expect(failedTask.errorSummary == "internal_failure: browser click failed")
    }

    @Test @MainActor func browserExecutionCoordinatorReleasesExecutorSessionWhenStopped() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let coordinator = AgentRuntimeExecutionCoordinator(store: store)

        await coordinator.drainBrowserTasksOnce()

        let session = try #require(store.agentRuntimeSessions.first(where: {
            $0.clientKind == .hostExecutor
        }))
        #expect(session.state == .active)

        coordinator.stop()

        let releasedSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == session.id }))
        #expect(releasedSession.state == .released)
        #expect(releasedSession.lastError == "coordinator_stopped")
    }
}
