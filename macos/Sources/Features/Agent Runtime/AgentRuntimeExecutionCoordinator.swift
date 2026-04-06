import Foundation

@MainActor
final class AgentRuntimeExecutionCoordinator {
    typealias BrowserCommandRunner = @MainActor (BrowserExternalCommandRequest) async -> BrowserExternalCommandResponse
    typealias DateProvider = @MainActor () -> Date
    typealias BrowserTabIDProvider = @MainActor () -> String?

    private enum ExecutionOutcome {
        case success
        case failure(String)
    }

    private static let browserPollIntervalSeconds: TimeInterval = 0.25
    private static let minimumBrowserHeartbeatIntervalSeconds: TimeInterval = 1
    private static let maximumBrowserHeartbeatIntervalSeconds: TimeInterval = 5
    private static let browserExecutorCapabilities = [
        AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
    ]
    private static let supportedBrowserTaskKinds: Set<AgentRuntimeTaskKind> = [
        .browserNavigation,
        .browserInteraction,
    ]

    private let store: AITerminalManagerStore
    private let now: DateProvider
    private let browserCommandRunner: BrowserCommandRunner
    private let defaultBrowserTabIDProvider: BrowserTabIDProvider

    private var browserExecutorSessionID: UUID?
    private var lastBrowserExecutorHeartbeatAt: Date?
    private var browserPollTimer: Timer?
    private var isDrainingBrowserTasks = false

    init(
        store: AITerminalManagerStore,
        now: @escaping DateProvider = Date.init,
        browserCommandRunner: @escaping BrowserCommandRunner = {
            await ScriptBrowserTab.routeExternalCommandAsync($0)
        },
        defaultBrowserTabIDProvider: @escaping BrowserTabIDProvider = {
            BrowserTabController.frontmostControllerID ?? BrowserTabController.all.last?.externalID
        }
    ) {
        self.store = store
        self.now = now
        self.browserCommandRunner = browserCommandRunner
        self.defaultBrowserTabIDProvider = defaultBrowserTabIDProvider
    }

    func start() {
        if browserPollTimer == nil {
            let timer = Timer(
                timeInterval: Self.browserPollIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.drainBrowserTasksOnce()
                }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            browserPollTimer = timer
        }

        Task { @MainActor in
            await self.drainBrowserTasksOnce()
        }
    }

    func stop() {
        browserPollTimer?.invalidate()
        browserPollTimer = nil
        releaseBrowserExecutorSession(reason: "coordinator_stopped")
    }

    func drainBrowserTasksOnce(now explicitNow: Date? = nil) async {
        guard !isDrainingBrowserTasks else { return }

        let now = explicitNow ?? self.now()
        guard store.agentRuntimeSettings.enabled else {
            releaseBrowserExecutorSession(reason: "runtime_disabled")
            return
        }

        guard let sessionID = ensureBrowserExecutorSession(now: now) else {
            return
        }

        isDrainingBrowserTasks = true
        defer { isDrainingBrowserTasks = false }

        while true {
            let claimNow = self.now()
            let claimedTask: AgentRuntimeTask
            do {
                guard let task = try store.claimNextAgentRuntimeTask(
                    sessionID: sessionID,
                    allowedKinds: Self.supportedBrowserTaskKinds,
                    now: claimNow
                ) else {
                    break
                }
                claimedTask = task
                _ = try store.updateAgentRuntimeTask(
                    sessionID: sessionID,
                    taskID: task.id,
                    state: .running,
                    now: claimNow
                )
            } catch {
                handleSessionMutationError(error)
                break
            }

            let outcome = await executeBrowserTask(claimedTask)
            let finishNow = self.now()

            do {
                switch outcome {
                case .success:
                    _ = try store.updateAgentRuntimeTask(
                        sessionID: sessionID,
                        taskID: claimedTask.id,
                        state: .completed,
                        now: finishNow
                    )
                case .failure(let message):
                    _ = try store.updateAgentRuntimeTask(
                        sessionID: sessionID,
                        taskID: claimedTask.id,
                        state: .failed,
                        errorSummary: message,
                        now: finishNow
                    )
                }

                _ = try store.heartbeatAgentRuntimeSession(
                    sessionID,
                    leaseDurationSeconds: AgentRuntimeSettings.maximumLeaseDurationSeconds,
                    now: finishNow
                )
                lastBrowserExecutorHeartbeatAt = finishNow
            } catch {
                handleSessionMutationError(error)
                break
            }
        }
    }

    private func ensureBrowserExecutorSession(now: Date) -> UUID? {
        if browserExecutorSessionID == nil {
            let existingSession = store.agentRuntimeSessions
                .filter { session in
                    session.clientKind == .hostExecutor
                        && session.state.isLeaseManaged
                        && session.capabilities.contains(AgentRuntimeCapability.runtimeExecutorBrowser.rawValue)
                }
                .sorted { lhs, rhs in
                    lhs.updatedAt > rhs.updatedAt
                }
                .first
            browserExecutorSessionID = existingSession?.id
            lastBrowserExecutorHeartbeatAt = existingSession?.lastHeartbeatAt ?? existingSession?.updatedAt
        }

        if let sessionID = browserExecutorSessionID {
            let leaseDurationSeconds = store.agentRuntimeSessions.first(where: { $0.id == sessionID })?.leaseDurationSeconds
                ?? AgentRuntimeSettings.maximumLeaseDurationSeconds
            guard shouldHeartbeatBrowserSession(
                now: now,
                leaseDurationSeconds: leaseDurationSeconds
            ) else {
                return sessionID
            }
            do {
                _ = try store.heartbeatAgentRuntimeSession(
                    sessionID,
                    leaseDurationSeconds: AgentRuntimeSettings.maximumLeaseDurationSeconds,
                    now: now
                )
                lastBrowserExecutorHeartbeatAt = now
                return sessionID
            } catch {
                browserExecutorSessionID = nil
                lastBrowserExecutorHeartbeatAt = nil
            }
        }

        do {
            let session = try store.registerAgentRuntimeSession(
                clientKind: .hostExecutor,
                capabilities: Self.browserExecutorCapabilities,
                leaseDurationSeconds: AgentRuntimeSettings.maximumLeaseDurationSeconds,
                now: now
            )
            browserExecutorSessionID = session.id
            lastBrowserExecutorHeartbeatAt = now
            return session.id
        } catch {
            browserExecutorSessionID = nil
            lastBrowserExecutorHeartbeatAt = nil
            return nil
        }
    }

    private func releaseBrowserExecutorSession(reason: String) {
        guard let sessionID = browserExecutorSessionID else { return }
        browserExecutorSessionID = nil
        lastBrowserExecutorHeartbeatAt = nil

        do {
            _ = try store.releaseAgentRuntimeSession(
                sessionID,
                reason: reason,
                now: now()
            )
        } catch {
            // Best effort only. The session will be naturally recovered if the
            // store already considers it missing, expired, or disabled.
        }
    }

    private func handleSessionMutationError(_ error: Error) {
        if let runtimeError = error as? AgentRuntimeStoreError {
            switch runtimeError {
            case .runtimeDisabled:
                releaseBrowserExecutorSession(reason: "runtime_disabled")
            case .sessionNotFound, .sessionExpired:
                browserExecutorSessionID = nil
                lastBrowserExecutorHeartbeatAt = nil
            default:
                break
            }
        }
    }

    private func executeBrowserTask(_ task: AgentRuntimeTask) async -> ExecutionOutcome {
        let request: BrowserExternalCommandRequest
        do {
            request = try makeBrowserRequest(for: task)
        } catch let error as AgentRuntimeBrowserExecutionError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }

        let response = await browserCommandRunner(request)
        guard response.ok else {
            return .failure(formattedBrowserError(response.error))
        }
        return .success
    }

    private func makeBrowserRequest(
        for task: AgentRuntimeTask
    ) throws -> BrowserExternalCommandRequest {
        switch task.kind {
        case .browserNavigation:
            return try makeBrowserNavigationRequest(for: task)
        case .browserInteraction:
            return try makeBrowserInteractionRequest(for: task)
        default:
            throw AgentRuntimeBrowserExecutionError.unsupportedTaskKind(task.kind.rawValue)
        }
    }

    private func makeBrowserNavigationRequest(
        for task: AgentRuntimeTask
    ) throws -> BrowserExternalCommandRequest {
        let metadata = task.payload.metadata
        guard let rawURL = firstNonEmpty(
            metadataValue(in: metadata, keys: "url"),
            task.payload.text
        ) else {
            throw AgentRuntimeBrowserExecutionError.invalidPayload("browser_navigation requires a URL.")
        }

        let target = resolveBrowserTarget(
            metadata: metadata,
            fallbackBrowserTabID: nil
        )

        if target.browserTabID != nil || target.browserContextID != nil {
            return BrowserExternalCommandRequest(
                command: .loadURL,
                browserTabID: target.browserTabID,
                browserContextID: target.browserContextID,
                pageID: target.pageID,
                frameName: target.frameName,
                documentRevision: target.documentRevision,
                payload: ["url": rawURL]
            )
        }

        return BrowserExternalCommandRequest(
            command: .newTab,
            payload: ["url": rawURL]
        )
    }

    private func makeBrowserInteractionRequest(
        for task: AgentRuntimeTask
    ) throws -> BrowserExternalCommandRequest {
        let metadata = task.payload.metadata
        guard let rawAction = metadataValue(in: metadata, keys: "action") else {
            throw AgentRuntimeBrowserExecutionError.invalidPayload("browser_interaction requires metadata.action.")
        }

        let target = resolveBrowserTarget(
            metadata: metadata,
            fallbackBrowserTabID: defaultBrowserTabIDProvider()
        )

        guard target.browserTabID != nil || target.browserContextID != nil else {
            throw AgentRuntimeBrowserExecutionError.invalidPayload(
                "browser_interaction requires metadata.browser_tab_id or a live frontmost Browser tab."
            )
        }

        let normalizedAction = normalizeAction(rawAction)
        let command: BrowserExternalCommandKind
        let payload: [String: String]

        switch normalizedAction {
        case "click":
            guard let selector = metadataValue(in: metadata, keys: "selector") else {
                throw AgentRuntimeBrowserExecutionError.invalidPayload("click requires metadata.selector.")
            }
            command = .click
            payload = includeOptionalValues([
                "selector": selector,
                "clickMode": metadataValue(in: metadata, keys: "clickMode", "click_mode"),
                "timeoutMS": metadataValue(in: metadata, keys: "timeoutMS", "timeout_ms"),
            ])

        case "type", "typetext":
            guard let selector = metadataValue(in: metadata, keys: "selector") else {
                throw AgentRuntimeBrowserExecutionError.invalidPayload("type_text requires metadata.selector.")
            }
            guard let text = firstNonEmpty(
                metadataValue(in: metadata, keys: "text"),
                task.payload.text
            ) else {
                throw AgentRuntimeBrowserExecutionError.invalidPayload("type_text requires text or payload.text.")
            }
            command = .typeText
            payload = includeOptionalValues([
                "selector": selector,
                "text": text,
                "timeoutMS": metadataValue(in: metadata, keys: "timeoutMS", "timeout_ms"),
            ])

        case "waitforselector":
            guard let selector = metadataValue(in: metadata, keys: "selector") else {
                throw AgentRuntimeBrowserExecutionError.invalidPayload("wait_for_selector requires metadata.selector.")
            }
            command = .waitForSelector
            payload = includeOptionalValues([
                "selector": selector,
                "timeoutMS": metadataValue(in: metadata, keys: "timeoutMS", "timeout_ms"),
                "pollIntervalMS": metadataValue(in: metadata, keys: "pollIntervalMS", "poll_interval_ms"),
                "waitMode": metadataValue(in: metadata, keys: "waitMode", "wait_mode"),
            ])

        case "evaluatejavascript", "eval":
            guard let script = firstNonEmpty(
                metadataValue(in: metadata, keys: "script"),
                task.payload.text
            ) else {
                throw AgentRuntimeBrowserExecutionError.invalidPayload(
                    "evaluate_javascript requires metadata.script or payload.text."
                )
            }
            command = .evaluateJavaScript
            payload = ["script": script]

        case "reload":
            command = .reload
            payload = [:]

        case "goback":
            command = .goBack
            payload = [:]

        case "goforward":
            command = .goForward
            payload = [:]

        default:
            throw AgentRuntimeBrowserExecutionError.unsupportedAction(rawAction)
        }

        return BrowserExternalCommandRequest(
            command: command,
            browserTabID: target.browserTabID,
            browserContextID: target.browserContextID,
            pageID: target.pageID,
            frameName: target.frameName,
            documentRevision: target.documentRevision,
            payload: payload
        )
    }

    private func resolveBrowserTarget(
        metadata: [String: String],
        fallbackBrowserTabID: String?
    ) -> BrowserCommandTarget {
        BrowserCommandTarget(
            browserTabID: firstNonEmpty(
                metadataValue(in: metadata, keys: "browserTabID", "browser_tab_id"),
                fallbackBrowserTabID
            ),
            browserContextID: metadataValue(in: metadata, keys: "browserContextID", "browser_context_id"),
            pageID: metadataValue(in: metadata, keys: "pageID", "page_id"),
            frameName: metadataValue(in: metadata, keys: "frameName", "frame_name"),
            documentRevision: parseOptionalInt(
                metadataValue(in: metadata, keys: "documentRevision", "document_revision")
            )
        )
    }

    private func metadataValue(
        in metadata: [String: String],
        keys: String...
    ) -> String? {
        firstNonEmpty(keys.compactMap { metadata[$0] })
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        firstNonEmpty(values)
    }

    private func firstNonEmpty<S: Sequence>(_ values: S) -> String? where S.Element == String? {
        for value in values {
            if let trimmed = trimmed(value), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func includeOptionalValues(_ values: [String: String?]) -> [String: String] {
        values.reduce(into: [String: String]()) { result, entry in
            guard let value = trimmed(entry.value), !value.isEmpty else { return }
            result[entry.key] = value
        }
    }

    private func normalizeAction(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func parseOptionalInt(_ rawValue: String?) -> Int? {
        guard let value = trimmed(rawValue) else { return nil }
        return Int(value)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedBrowserError(_ error: BrowserExternalCommandError?) -> String {
        guard let error else {
            return "Browser execution failed without an error payload."
        }
        return "\(error.code): \(error.message)"
    }

    private func shouldHeartbeatBrowserSession(
        now: Date,
        leaseDurationSeconds: Double
    ) -> Bool {
        guard let lastHeartbeatAt = lastBrowserExecutorHeartbeatAt else {
            return true
        }

        let interval = min(
            max(
                leaseDurationSeconds / 3,
                Self.minimumBrowserHeartbeatIntervalSeconds
            ),
            Self.maximumBrowserHeartbeatIntervalSeconds
        )
        return now.timeIntervalSince(lastHeartbeatAt) >= interval
    }
}

private struct BrowserCommandTarget {
    let browserTabID: String?
    let browserContextID: String?
    let pageID: String?
    let frameName: String?
    let documentRevision: Int?
}

private enum AgentRuntimeBrowserExecutionError: LocalizedError {
    case invalidPayload(String)
    case unsupportedAction(String)
    case unsupportedTaskKind(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload(let message):
            return message
        case .unsupportedAction(let action):
            return "Unsupported browser_interaction action: \(action)."
        case .unsupportedTaskKind(let kind):
            return "Unsupported browser executor task kind: \(kind)."
        }
    }
}
