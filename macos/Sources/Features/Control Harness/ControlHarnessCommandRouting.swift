import Foundation

struct ControlHarnessRequestTarget: Codable, Hashable {
    let workspaceID: String?
    let tabID: String?
    let parentTabID: String?
    let terminalID: String?
    let todoID: String?
    let subscriptionID: String?
    let windowNumber: Int?
    let panelID: String?
    let panelTabID: String?
    let browserTabID: String?
    let browserContextID: String?
    let pageID: String?
    let frameName: String?
    let taskID: String?
    let scheduleID: String?
    let documentRevision: Int?

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case parentTabID = "parent_tab_id"
        case terminalID = "terminal_id"
        case todoID = "todo_id"
        case subscriptionID = "subscription_id"
        case windowNumber = "window_number"
        case panelID = "panel_id"
        case panelTabID = "panel_tab_id"
        case browserTabID = "browser_tab_id"
        case browserContextID = "browser_context_id"
        case pageID = "page_id"
        case frameName = "frame_name"
        case taskID = "task_id"
        case scheduleID = "schedule_id"
        case documentRevision = "document_revision"
    }

    init(
        workspaceID: String? = nil,
        tabID: String? = nil,
        parentTabID: String? = nil,
        terminalID: String? = nil,
        todoID: String? = nil,
        subscriptionID: String? = nil,
        windowNumber: Int? = nil,
        panelID: String? = nil,
        panelTabID: String? = nil,
        browserTabID: String? = nil,
        browserContextID: String? = nil,
        pageID: String? = nil,
        frameName: String? = nil,
        taskID: String? = nil,
        scheduleID: String? = nil,
        documentRevision: Int? = nil
    ) {
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.parentTabID = parentTabID
        self.terminalID = terminalID
        self.todoID = todoID
        self.subscriptionID = subscriptionID
        self.windowNumber = windowNumber
        self.panelID = panelID
        self.panelTabID = panelTabID
        self.browserTabID = browserTabID
        self.browserContextID = browserContextID
        self.pageID = pageID
        self.frameName = frameName
        self.taskID = taskID
        self.scheduleID = scheduleID
        self.documentRevision = documentRevision
    }
}

struct ControlHarnessRequestOptions: Codable, Hashable {
    let expectedGeneration: Int?
    let sinceSequence: Int64?
    let eventLimit: Int?
    let maxChars: Int?
    let maxLines: Int?
    let cursor: String?
    let readAfterWriteID: String?
    let timeoutMS: Int?

    enum CodingKeys: String, CodingKey {
        case expectedGeneration = "expected_generation"
        case sinceSequence = "since_sequence"
        case eventLimit = "event_limit"
        case maxChars = "max_chars"
        case maxLines = "max_lines"
        case cursor
        case readAfterWriteID = "read_after_write_id"
        case timeoutMS = "timeout_ms"
    }
}

enum ControlHarnessJSONValue: Hashable, Codable {
    case object([String: ControlHarnessJSONValue])
    case array([ControlHarnessJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: ControlHarnessJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(ControlHarnessJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [ControlHarnessJSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(ControlHarnessJSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let value):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, item) in value {
                guard let codingKey = DynamicCodingKey(stringValue: key) else {
                    continue
                }
                try container.encode(item, forKey: codingKey)
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for item in value {
                try container.encode(item)
            }
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ControlCommandCompatibilityEntry: Hashable {
    let legacyCommand: String
    let replacementCommands: [String]
    let detail: String
}

enum ControlHarnessCommandAliases {
    static let legacySupportedCommands = [
        "handshake",
        "snapshot",
        "agent.runtime.snapshot",
        "agent.runtime.session.register",
        "agent.runtime.session.heartbeat",
        "agent.runtime.session.release",
        "agent.runtime.task.enqueue",
        "agent.runtime.task.claim",
        "agent.runtime.task.claim_next",
        "agent.runtime.task.update",
        "agent.runtime.task.approve",
        "agent.runtime.task.cancel",
        "agent.runtime.schedule.enqueue",
        "agent.runtime.schedule.update",
        "agent.runtime.schedule.cancel",
        "new-tab",
        "close-tab",
        "rename-tab",
        "send-text",
        "send-key",
        "run-command",
        "read-terminal",
        "terminal.stream.open",
        "terminal.stream.ack",
        "terminal.snapshot.v2",
        "terminal.semantic.v2",
        "close-terminal",
        "todo-snapshot",
        "todo-add",
        "todo-update",
        "todo-complete",
        "todo-assign",
        "todo-sync-stale",
        "events.subscribe",
    ]

    static let namespaceAliases: [String: String] = [
        "system.handshake": "handshake",
        "state.snapshot": "snapshot",
        "system.target.resolve": "system.target.resolve",
        "system.capabilities.get": "system.capabilities.get",
        "app.state.get": "app.state.get",
        "app.relaunch": "app.relaunch",
        "workspace.snapshot": "snapshot",
        "workspace.tab.snapshot": "snapshot",
        "tab.new": "new-tab",
        "workspace.tab.create": "new-tab",
        "tab.close": "close-tab",
        "workspace.tab.close": "close-tab",
        "tab.rename": "rename-tab",
        "terminal.write": "send-text",
        "terminal.input.send": "send-text",
        "terminal.key": "send-key",
        "terminal.run": "run-command",
        "terminal.command.run": "run-command",
        "terminal.read": "read-terminal",
        "terminal.output.read": "read-terminal",
        "terminal.close": "close-terminal",
        "terminal.session.close": "close-terminal",
        "terminal.snapshot": "terminal.snapshot.v2",
        "terminal.semantic": "terminal.semantic.v2",
        "runtime.snapshot": "agent.runtime.snapshot",
        "runtime.session.register": "agent.runtime.session.register",
        "runtime.session.heartbeat": "agent.runtime.session.heartbeat",
        "runtime.session.release": "agent.runtime.session.release",
        "runtime.task.enqueue": "agent.runtime.task.enqueue",
        "runtime.task.claim": "agent.runtime.task.claim",
        "runtime.task.claimNext": "agent.runtime.task.claim_next",
        "runtime.task.claim_next": "agent.runtime.task.claim_next",
        "runtime.task.update": "agent.runtime.task.update",
        "runtime.task.approve": "agent.runtime.task.approve",
        "runtime.task.cancel": "agent.runtime.task.cancel",
        "runtime.schedule.enqueue": "agent.runtime.schedule.enqueue",
        "runtime.schedule.update": "agent.runtime.schedule.update",
        "runtime.schedule.cancel": "agent.runtime.schedule.cancel",
        "todo.snapshot": "todo-snapshot",
        "todo.item.list": "todo-snapshot",
        "todo.add": "todo-add",
        "todo.item.create": "todo-add",
        "todo.update": "todo-update",
        "todo.item.update": "todo-update",
        "todo.complete": "todo-complete",
        "todo.item.complete": "todo-complete",
        "todo.assign": "todo-assign",
        "todo.item.assign": "todo-assign",
        "todo.syncStale": "todo-sync-stale",
        "todo.item.sync_stale": "todo-sync-stale",
        "window.list": "window.list",
        "window.focus": "window.focus",
        "window.show": "window.show",
        "window.hide": "window.hide",
        "window.close": "window.close",
        "window.tabOverview.toggle": "window.tabOverview.toggle",
        "window.floatOnTop.set": "window.floatOnTop.set",
        "panel.list": "panel.list",
        "panel.open": "panel.open",
        "panel.focus": "panel.focus",
        "panel.close": "panel.close",
        "panel.tab.select": "panel.tab.select",
        "panel.state.get": "panel.state.get",
        "settings.schema.get": "settings.schema.get",
        "settings.values.get": "settings.values.get",
        "settings.values.set": "settings.values.set",
        "settings.validate": "settings.validate",
        "settings.apply": "settings.apply",
        "settings.reset": "settings.reset",
        "settings.diff": "settings.diff",
        "diagnostics.metrics.get": "diagnostics.metrics.get",
        "diagnostics.metrics.reset": "diagnostics.metrics.reset",
        "diagnostics.logs.tail": "diagnostics.logs.tail",
        "diagnostics.errors.recent": "diagnostics.errors.recent",
        "diagnostics.audit.query": "diagnostics.audit.query",
        "diagnostics.eventBuffer.status": "diagnostics.eventBuffer.status",
    ]

    static let unifiedSupportedCommands = [
        "system.handshake",
        "state.snapshot",
        "system.target.resolve",
        "system.capabilities.get",
        "app.state.get",
        "app.relaunch",
        "workspace.snapshot",
        "workspace.tab.snapshot",
        "tab.new",
        "workspace.tab.create",
        "tab.close",
        "workspace.tab.close",
        "tab.rename",
        "terminal.write",
        "terminal.input.send",
        "terminal.key",
        "terminal.run",
        "terminal.command.run",
        "terminal.read",
        "terminal.output.read",
        "terminal.close",
        "terminal.session.close",
        "terminal.stream.open",
        "terminal.stream.ack",
        "terminal.snapshot",
        "terminal.semantic",
        "runtime.snapshot",
        "runtime.session.register",
        "runtime.session.heartbeat",
        "runtime.session.release",
        "runtime.task.enqueue",
        "runtime.task.claim",
        "runtime.task.claimNext",
        "runtime.task.claim_next",
        "runtime.task.update",
        "runtime.task.approve",
        "runtime.task.cancel",
        "runtime.schedule.enqueue",
        "runtime.schedule.update",
        "runtime.schedule.cancel",
        "todo.snapshot",
        "todo.item.list",
        "todo.add",
        "todo.item.create",
        "todo.update",
        "todo.item.update",
        "todo.complete",
        "todo.item.complete",
        "todo.assign",
        "todo.item.assign",
        "todo.syncStale",
        "todo.item.sync_stale",
        "window.list",
        "window.focus",
        "window.show",
        "window.hide",
        "window.close",
        "window.tabOverview.toggle",
        "window.floatOnTop.set",
        "panel.list",
        "panel.open",
        "panel.focus",
        "panel.close",
        "panel.tab.select",
        "panel.state.get",
        "settings.schema.get",
        "settings.values.get",
        "settings.values.set",
        "settings.validate",
        "settings.apply",
        "settings.reset",
        "settings.diff",
        "diagnostics.metrics.get",
        "diagnostics.metrics.reset",
        "diagnostics.logs.tail",
        "diagnostics.errors.recent",
        "diagnostics.audit.query",
        "diagnostics.eventBuffer.status",
        "events.subscribe",
        "events.stream.subscribe",
        "events.stream.drain",
        "events.stream.unsubscribe",
    ]

    static var allSupportedCommands: [String] {
        Array(
            Set(
                legacySupportedCommands
                    + unifiedSupportedCommands
                    + ControlHarnessBrowserCommandAdapter.supportedCommands
            )
        ).sorted()
    }

    static func normalize(_ command: String) -> String {
        namespaceAliases[command] ?? command
    }
}

extension ControlHarnessRequest {
    var normalizedCommand: String {
        ControlHarnessCommandAliases.normalize(command)
    }

    func normalized() -> ControlHarnessRequest {
        let normalizedPayload = mergedStringMaps(payload, additional: optionsPayload)
        return ControlHarnessRequest(
            requestID: requestID,
            protocolVersion: protocolVersion,
            authToken: authToken,
            transportMode: transportMode,
            encryptedPayload: encryptedPayload,
            command: normalizedCommand,
            date: date,
            tabID: tabID ?? target?.tabID,
            parentTabID: parentTabID ?? target?.parentTabID,
            terminalID: terminalID ?? target?.terminalID,
            todoID: todoID ?? target?.todoID,
            windowNumber: windowNumber ?? target?.windowNumber,
            panelID: panelID ?? target?.panelID,
            panelTabID: panelTabID ?? target?.panelTabID,
            scope: scope,
            text: text,
            terminalKey: terminalKey,
            commandText: commandText,
            workingDirectory: workingDirectory,
            title: title,
            notes: notes,
            environment: environment,
            force: force,
            completed: completed,
            workspaceID: workspaceID ?? target?.workspaceID,
            includeCompleted: includeCompleted,
            client: client,
            deviceID: deviceID,
            deviceLabel: deviceLabel,
            desktopID: desktopID,
            idempotencyKey: idempotencyKey,
            expectedGeneration: expectedGeneration ?? options?.expectedGeneration,
            sinceSequence: sinceSequence ?? options?.sinceSequence,
            eventLimit: eventLimit ?? options?.eventLimit,
            mode: mode,
            sinceFrameID: sinceFrameID,
            maxChars: maxChars ?? options?.maxChars,
            maxLines: maxLines ?? options?.maxLines,
            cursor: cursor ?? options?.cursor,
            readAfterWriteID: readAfterWriteID ?? options?.readAfterWriteID,
            streamID: streamID ?? target?.subscriptionID,
            ackBytes: ackBytes,
            lastAckSequence: lastAckSequence,
            pairingCode: pairingCode,
            requestedScopes: requestedScopes,
            sessionID: sessionID,
            taskID: taskID ?? target?.taskID,
            scheduleID: scheduleID ?? target?.scheduleID,
            capabilities: capabilities,
            leaseDurationSeconds: leaseDurationSeconds,
            taskKind: taskKind,
            taskKinds: taskKinds,
            recurrenceMode: recurrenceMode,
            intervalSeconds: intervalSeconds,
            priority: priority,
            scheduledAt: scheduledAt,
            maxRetryCount: maxRetryCount,
            metadata: metadata,
            taskState: taskState,
            scheduleState: scheduleState,
            errorSummary: errorSummary,
            reason: reason,
            desktopLabel: desktopLabel,
            upstreamHost: upstreamHost,
            upstreamPort: upstreamPort,
            browserTabID: browserTabID ?? target?.browserTabID,
            browserContextID: browserContextID ?? target?.browserContextID,
            pageID: pageID ?? target?.pageID,
            frameName: frameName ?? target?.frameName,
            documentRevision: documentRevision ?? target?.documentRevision,
            payload: normalizedPayload,
            target: target,
            options: options
        )
    }

    private var optionsPayload: [String: String]? {
        var derivedPayload: [String: String] = [:]
        if let timeoutMS = options?.timeoutMS {
            derivedPayload["timeoutMS"] = String(timeoutMS)
        }
        return derivedPayload.isEmpty ? nil : derivedPayload
    }

    private func mergedStringMaps(
        _ base: [String: String]?,
        additional: [String: String]?
    ) -> [String: String]? {
        var result = base ?? [:]
        if let additional {
            for (key, value) in additional where result[key] == nil {
                result[key] = value
            }
        }
        return result.isEmpty ? nil : result
    }
}

enum ControlHarnessBrowserCommandAdapter {
    private static let protocolAliasCommandMap: [String: String] = [
        "browser.tab.create": "browser.tab.new",
        "browser.page.get_active": "browser.page.getActive",
        "browser.page.navigate": "browser.page.load",
        "browser.dom.wait": "browser.dom.waitFor",
        "browser.script.eval": "browser.dom.eval",
    ]

    private static let canonicalCommandMap: [String: BrowserExternalCommandKind] = [
        "browser.tab.list": .listTabs,
        "browser.tab.new": .newTab,
        "browser.context.list": .listContexts,
        "browser.context.get": .getContext,
        "browser.context.new": .newContext,
        "browser.context.close": .closeContext,
        "browser.context.activate": .activateContext,
        "browser.page.list": .listPages,
        "browser.page.new": .newPageInContext,
        "browser.page.getActive": .getActivePage,
        "browser.page.activate": .activatePage,
        "browser.page.close": .closePage,
        "browser.page.load": .loadURL,
        "browser.page.back": .goBack,
        "browser.page.forward": .goForward,
        "browser.page.reload": .reload,
        "browser.frame.list": .listFrames,
        "browser.debug.status": .getDebugStatus,
        "browser.cookie.get": .getCookies,
        "browser.cookie.set": .setCookie,
        "browser.cookie.delete": .deleteCookie,
        "browser.cookie.clear": .clearCookies,
        "browser.dom.eval": .evaluateJavaScript,
        "browser.dom.query": .query,
        "browser.dom.click": .click,
        "browser.dom.type": .typeText,
        "browser.dom.waitFor": .waitForSelector,
        "browser.dom.getText": .getText,
        "browser.dom.getAttributes": .getAttributes,
        "browser.dom.getBoundingBox": .getBoundingBox,
        "browser.dom.snapshot": .getDOMSnapshot,
        "browser.dom.batch": .runDOMBatch,
        "browser.event.subscribe": .subscribeEvents,
        "browser.event.drain": .drainEvents,
        "browser.event.unsubscribe": .unsubscribeEvents,
        "browser.prompt.resolveDialog": .resolveDialog,
        "browser.prompt.resolvePermission": .resolvePermission,
        "browser.prompt.resolveAuth": .resolveAuth,
        "browser.prompt.resolveCertificate": .resolveCertificate,
        "browser.download.cancel": .cancelDownload,
    ]

    private static let rawAliasCommandMap: [String: BrowserExternalCommandKind] = [
        "browser.listTabs": .listTabs,
        "browser.newTab": .newTab,
        "browser.listContexts": .listContexts,
        "browser.getContext": .getContext,
        "browser.newContext": .newContext,
        "browser.closeContext": .closeContext,
        "browser.activateContext": .activateContext,
        "browser.listPages": .listPages,
        "browser.newPageInContext": .newPageInContext,
        "browser.getActivePage": .getActivePage,
        "browser.activatePage": .activatePage,
        "browser.closePage": .closePage,
        "browser.listFrames": .listFrames,
        "browser.getDebugStatus": .getDebugStatus,
        "browser.loadURL": .loadURL,
        "browser.goBack": .goBack,
        "browser.goForward": .goForward,
        "browser.reload": .reload,
        "browser.getCookies": .getCookies,
        "browser.setCookie": .setCookie,
        "browser.deleteCookie": .deleteCookie,
        "browser.clearCookies": .clearCookies,
        "browser.evaluateJavaScript": .evaluateJavaScript,
        "browser.query": .query,
        "browser.click": .click,
        "browser.typeText": .typeText,
        "browser.waitForSelector": .waitForSelector,
        "browser.getText": .getText,
        "browser.getAttributes": .getAttributes,
        "browser.getBoundingBox": .getBoundingBox,
        "browser.getDOMSnapshot": .getDOMSnapshot,
        "browser.runDOMBatch": .runDOMBatch,
        "browser.subscribeEvents": .subscribeEvents,
        "browser.drainEvents": .drainEvents,
        "browser.unsubscribeEvents": .unsubscribeEvents,
        "browser.resolveDialog": .resolveDialog,
        "browser.resolvePermission": .resolvePermission,
        "browser.resolveAuth": .resolveAuth,
        "browser.resolveCertificate": .resolveCertificate,
        "browser.cancelDownload": .cancelDownload,
    ]

    private static let commandMap = canonicalCommandMap
        .merging(protocolAliasCommandMap.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = canonicalCommandMap[entry.value]
        }) { canonical, _ in canonical }
        .merging(rawAliasCommandMap) { canonical, _ in canonical }

    private static let canonicalCommandSet = Set(canonicalCommandMap.keys)

    private static let inputCommands: Set<String> = [
        "browser.dom.click",
        "browser.dom.type",
    ]

    private static let mutationCommands: Set<String> = [
        "browser.tab.new",
        "browser.context.new",
        "browser.context.close",
        "browser.context.activate",
        "browser.page.new",
        "browser.page.activate",
        "browser.page.close",
        "browser.page.load",
        "browser.page.back",
        "browser.page.forward",
        "browser.page.reload",
        "browser.cookie.set",
        "browser.cookie.delete",
        "browser.cookie.clear",
        "browser.dom.eval",
        "browser.dom.click",
        "browser.dom.type",
        "browser.dom.batch",
        "browser.prompt.resolveDialog",
        "browser.prompt.resolvePermission",
        "browser.prompt.resolveAuth",
        "browser.prompt.resolveCertificate",
        "browser.download.cancel",
    ]

    private static let resyncCommands: Set<String> = [
        "browser.event.subscribe",
        "browser.event.drain",
        "browser.event.unsubscribe",
    ]

    private static let asyncRoutedCommands: Set<BrowserExternalCommandKind> = [
        .newTab,
        .newContext,
        .newPageInContext,
        .listFrames,
        .loadURL,
        .goBack,
        .goForward,
        .reload,
        .getCookies,
        .setCookie,
        .deleteCookie,
        .clearCookies,
        .evaluateJavaScript,
        .query,
        .click,
        .typeText,
        .waitForSelector,
        .getText,
        .getAttributes,
        .getBoundingBox,
        .getDOMSnapshot,
        .runDOMBatch,
        .resolveDialog,
        .resolvePermission,
        .resolveAuth,
        .resolveCertificate,
        .cancelDownload,
    ]

    static var supportedCommands: [String] {
        Array(
            canonicalCommandSet
                .union(protocolAliasCommandMap.keys)
                .union(rawAliasCommandMap.keys)
        ).sorted()
    }

    static var compatibilityEntries: [ControlCommandCompatibilityEntry] {
        let aliases = Set(protocolAliasCommandMap.keys).union(rawAliasCommandMap.keys)
        return aliases.sorted().map { alias in
            let canonical = canonicalCommand(for: alias)
            return ControlCommandCompatibilityEntry(
                legacyCommand: alias,
                replacementCommands: [canonical],
                detail: "Use \(canonical) for new browser.tab.v1 clients. \(alias) remains supported for compatibility."
            )
        }
    }

    static func isBrowserCommand(_ command: String) -> Bool {
        commandMap[canonicalCommand(for: command)] != nil
    }

    static func isMutation(_ command: String) -> Bool {
        mutationCommands.contains(canonicalCommand(for: command))
    }

    static func isInput(_ command: String) -> Bool {
        inputCommands.contains(canonicalCommand(for: command))
    }

    static func isSubscription(_ command: String) -> Bool {
        false
    }

    static func isObserve(_ command: String) -> Bool {
        isBrowserCommand(command) && !isMutation(command)
    }

    static func isResync(_ command: String) -> Bool {
        resyncCommands.contains(canonicalCommand(for: command))
    }

    @MainActor
    static func execute(_ request: ControlHarnessRequest) throws -> AnyEncodable {
        let browserRequest = try makeRequest(from: request)
        let response = ScriptBrowserTab.routeExternalCommand(browserRequest)
        return try encodeResponse(response, request: browserRequest)
    }

    @MainActor
    static func executeAsync(_ request: ControlHarnessRequest) async throws -> AnyEncodable {
        let browserRequest = try makeRequest(from: request)
        let response: BrowserExternalCommandResponse
        if asyncRoutedCommands.contains(browserRequest.command) {
            response = await ScriptBrowserTab.routeExternalCommandAsync(browserRequest)
        } else {
            response = ScriptBrowserTab.routeExternalCommand(browserRequest)
        }
        return try encodeResponse(response, request: browserRequest)
    }

    private static func encodeResponse(
        _ response: BrowserExternalCommandResponse,
        request: BrowserExternalCommandRequest
    ) throws -> AnyEncodable {
        guard response.ok else {
            throw mapError(response.error)
        }

        guard let resultJSON = response.resultJSON,
              resultJSON.isEmpty == false,
              let data = resultJSON.data(using: .utf8)
        else {
            return AnyEncodable(ControlHarnessJSONValue.null)
        }

        if let decoded = try? JSONDecoder().decode(ControlHarnessJSONValue.self, from: data) {
            return AnyEncodable(decoded)
        }

        return AnyEncodable(ControlHarnessJSONValue.string(resultJSON))
    }

    static func makeRequest(from request: ControlHarnessRequest) throws -> BrowserExternalCommandRequest {
        let normalized = request.normalized()
        let canonical = canonicalCommand(for: normalized.command)
        guard let browserCommand = commandMap[canonical] else {
            throw ControlHarnessCoreError.unsupportedCommand(normalized.command)
        }

        let normalizedPayload = normalizedBrowserPayload(
            for: canonical,
            payload: normalized.payload ?? [:]
        )

        return BrowserExternalCommandRequest(
            id: UUID(uuidString: normalized.requestID) ?? UUID(),
            version: browserProtocolVersion(for: canonical),
            command: browserCommand,
            browserTabID: normalized.browserTabID,
            browserContextID: normalized.browserContextID,
            pageID: normalized.pageID,
            frameName: normalized.frameName,
            documentRevision: normalized.documentRevision,
            payload: normalizedPayload
        )
    }

    static func canonicalCommand(for command: String) -> String {
        if canonicalCommandSet.contains(command) {
            return command
        }

        if let aliased = protocolAliasCommandMap[command] {
            return aliased
        }

        guard let kind = rawAliasCommandMap[command] else {
            return command
        }

        switch kind {
        case .listTabs:
            return "browser.tab.list"
        case .newTab:
            return "browser.tab.new"
        case .listContexts:
            return "browser.context.list"
        case .getContext:
            return "browser.context.get"
        case .newContext:
            return "browser.context.new"
        case .closeContext:
            return "browser.context.close"
        case .activateContext:
            return "browser.context.activate"
        case .listPages:
            return "browser.page.list"
        case .newPageInContext:
            return "browser.page.new"
        case .getActivePage:
            return "browser.page.getActive"
        case .activatePage:
            return "browser.page.activate"
        case .closePage:
            return "browser.page.close"
        case .loadURL:
            return "browser.page.load"
        case .goBack:
            return "browser.page.back"
        case .goForward:
            return "browser.page.forward"
        case .reload:
            return "browser.page.reload"
        case .listFrames:
            return "browser.frame.list"
        case .getDebugStatus:
            return "browser.debug.status"
        case .getCookies:
            return "browser.cookie.get"
        case .setCookie:
            return "browser.cookie.set"
        case .deleteCookie:
            return "browser.cookie.delete"
        case .clearCookies:
            return "browser.cookie.clear"
        case .evaluateJavaScript:
            return "browser.dom.eval"
        case .query:
            return "browser.dom.query"
        case .click:
            return "browser.dom.click"
        case .typeText:
            return "browser.dom.type"
        case .waitForSelector:
            return "browser.dom.waitFor"
        case .getText:
            return "browser.dom.getText"
        case .getAttributes:
            return "browser.dom.getAttributes"
        case .getBoundingBox:
            return "browser.dom.getBoundingBox"
        case .getDOMSnapshot:
            return "browser.dom.snapshot"
        case .runDOMBatch:
            return "browser.dom.batch"
        case .subscribeEvents:
            return "browser.event.subscribe"
        case .drainEvents:
            return "browser.event.drain"
        case .unsubscribeEvents:
            return "browser.event.unsubscribe"
        case .resolveDialog:
            return "browser.prompt.resolveDialog"
        case .resolvePermission:
            return "browser.prompt.resolvePermission"
        case .resolveAuth:
            return "browser.prompt.resolveAuth"
        case .resolveCertificate:
            return "browser.prompt.resolveCertificate"
        case .cancelDownload:
            return "browser.download.cancel"
        }
    }

    private static func browserProtocolVersion(for command: String) -> String {
        switch command {
        case let value where value.hasPrefix("browser.context."),
             let value where value.hasPrefix("browser.page."),
             let value where value.hasPrefix("browser.dom."),
             let value where value.hasPrefix("browser.frame."):
            return BrowserCommandProtocolVersion.v2
        default:
            return BrowserCommandProtocolVersion.v1
        }
    }

    private static func normalizedBrowserPayload(
        for command: String,
        payload: [String: String]
    ) -> [String: String] {
        guard command == "browser.event.subscribe" else {
            return payload
        }

        guard payload["kindsJSON"] == nil,
              let legacyKinds = payload["eventKinds"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              legacyKinds.isEmpty == false
        else {
            return payload
        }

        var normalizedPayload = payload
        if legacyKinds.hasPrefix("[") {
            normalizedPayload["kindsJSON"] = legacyKinds
            normalizedPayload.removeValue(forKey: "eventKinds")
            return normalizedPayload
        }

        let kinds = legacyKinds
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let encodedKinds = try? JSONEncoder().encode(kinds),
              let kindsJSON = String(data: encodedKinds, encoding: .utf8)
        else {
            return payload
        }

        normalizedPayload["kindsJSON"] = kindsJSON
        normalizedPayload.removeValue(forKey: "eventKinds")
        return normalizedPayload
    }

    private static func mapError(_ error: BrowserExternalCommandError?) -> ControlHarnessCoreError {
        guard let error else {
            return .internalFailure
        }

        switch error.code {
        case "invalid_request":
            return .invalidArgument(error.message)
        case "unsupported_version":
            return .unsupportedProtocolVersion(error.message)
        case "stale_document_revision":
            return .operationFailed("stale_document_revision: \(error.message)")
        default:
            return .operationFailed("\(error.code): \(error.message)")
        }
    }
}
