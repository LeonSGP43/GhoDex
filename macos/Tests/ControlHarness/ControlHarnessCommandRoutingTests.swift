import Foundation
import Testing
@testable import GhoDex

private struct RoutingCapabilitiesEnvelope: Decodable {
    let requestID: String
    let status: String
    let result: RoutingCapabilitiesPayload?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case result
        case errorCode = "error_code"
    }
}

private struct RoutingCapabilitiesPayload: Decodable {
    let protocolVersion: String
    let commands: [String]
    let compatibility: RoutingCompatibilityPayload

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case commands
        case compatibility
    }
}

private struct RoutingCompatibilityPayload: Decodable {
    let authority: String
    let legacyCommands: [String]
    let migrations: [RoutingMigrationPayload]

    enum CodingKeys: String, CodingKey {
        case authority
        case legacyCommands = "legacy_commands"
        case migrations
    }
}

private struct RoutingMigrationPayload: Decodable {
    let command: String
    let replacementCommands: [String]
    let status: String

    enum CodingKeys: String, CodingKey {
        case command
        case replacementCommands = "replacement_commands"
        case status
    }
}

private func makeRoutingRequest(
    requestID: String = UUID().uuidString,
    command: String,
    text: String? = nil,
    terminalID: String? = nil,
    browserTabID: String? = nil,
    browserContextID: String? = nil,
    pageID: String? = nil,
    frameName: String? = nil,
    documentRevision: Int? = nil,
    payload: [String: String]? = nil,
    target: ControlHarnessRequestTarget? = nil,
    options: ControlHarnessRequestOptions? = nil
) -> ControlHarnessRequest {
    ControlHarnessRequest(
        requestID: requestID,
        protocolVersion: nil,
        command: command,
        tabID: nil,
        parentTabID: nil,
        terminalID: terminalID,
        scope: nil,
        text: text,
        commandText: nil,
        workingDirectory: nil,
        title: nil,
        environment: nil,
        force: nil,
        client: "tests",
        idempotencyKey: nil,
        expectedGeneration: nil,
        sinceSequence: nil,
        eventLimit: nil,
        mode: nil,
        sinceFrameID: nil,
        maxChars: nil,
        maxLines: nil,
        cursor: nil,
        readAfterWriteID: nil,
        browserTabID: browserTabID,
        browserContextID: browserContextID,
        pageID: pageID,
        frameName: frameName,
        documentRevision: documentRevision,
        payload: payload,
        target: target,
        options: options
    )
}

@MainActor
private func makeRoutingCore(bundleID: String = "ghdx.tests.command-routing") -> ControlHarnessCore {
    ControlHarnessCore(
        appDelegate: nil,
        auditLogger: ControlHarnessAuditLogger(bundleID: bundleID),
        sampleStore: ControlHarnessSampleStore()
    )
}

struct ControlHarnessCommandRoutingTests {
    @Test func normalizedRequestPromotesTargetOptionsAndAliases() {
        let terminalID = UUID().uuidString
        let request = makeRoutingRequest(
            command: "terminal.write",
            text: "echo hi",
            target: ControlHarnessRequestTarget(
                workspaceID: nil,
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID,
                todoID: nil,
                subscriptionID: nil,
                browserTabID: nil,
                browserContextID: nil,
                pageID: nil,
                frameName: nil,
                taskID: nil,
                scheduleID: nil,
                documentRevision: nil
            ),
            options: ControlHarnessRequestOptions(
                expectedGeneration: 7,
                sinceSequence: nil,
                eventLimit: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil,
                timeoutMS: 5000
            )
        )

        let normalized = request.normalized()
        #expect(normalized.command == "send-text")
        #expect(normalized.terminalID == terminalID)
        #expect(normalized.expectedGeneration == 7)
        #expect(normalized.payload?["timeoutMS"] == "5000")
    }

    @Test @MainActor func coreAcceptsNamespacedSnapshotAlias() {
        let core = makeRoutingCore(bundleID: "ghdx.tests.command-routing.snapshot")
        let response = core.handle(
            makeRoutingRequest(command: "state.snapshot"),
            socketPath: "/tmp/ghodex-control-routing.sock"
        )

        #expect(response.status == "ok")
        #expect(response.errorCode == nil)
    }

    @Test @MainActor func coreAcceptsSystemCompatibilityCommands() throws {
        let core = makeRoutingCore(bundleID: "ghdx.tests.command-routing.system")

        let resolveResponse = core.handle(
            makeRoutingRequest(command: "system.target.resolve"),
            socketPath: "/tmp/ghodex-control-routing.sock"
        )
        #expect(resolveResponse.status == "ok")
        #expect(resolveResponse.errorCode == nil)

        let capabilitiesResponse = core.handle(
            makeRoutingRequest(command: "system.capabilities.get"),
            socketPath: "/tmp/ghodex-control-routing.sock"
        )
        #expect(capabilitiesResponse.status == "ok")
        #expect(capabilitiesResponse.errorCode == nil)

        let encoded = try JSONEncoder().encode(capabilitiesResponse)
        let envelope = try JSONDecoder().decode(RoutingCapabilitiesEnvelope.self, from: encoded)
        let capabilities = try #require(envelope.result)
        #expect(capabilities.protocolVersion == ControlHarnessCore.protocolVersion)
        #expect(capabilities.commands.contains("events.stream.subscribe"))
        #expect(capabilities.compatibility.authority == "control_harness")
        #expect(capabilities.compatibility.legacyCommands.contains("events.subscribe"))
        let migration = try #require(capabilities.compatibility.migrations.first(where: { $0.command == "events.subscribe" }))
        #expect(migration.replacementCommands == ["events.stream.subscribe", "events.stream.drain", "events.stream.unsubscribe"])
        #expect(migration.status == "legacy_supported")
    }

    @Test func normalizedRequestAcceptsProjectCanonicalCommands() {
        let terminalID = UUID().uuidString
        let todoID = UUID().uuidString

        #expect(
            makeRoutingRequest(command: "workspace.tab.snapshot").normalized().command == "snapshot"
        )
        #expect(
            makeRoutingRequest(command: "terminal.command.run", terminalID: terminalID).normalized().command == "run-command"
        )
        #expect(
            makeRoutingRequest(command: "todo.item.update", target: ControlHarnessRequestTarget(
                workspaceID: nil,
                tabID: nil,
                parentTabID: nil,
                terminalID: nil,
                todoID: todoID,
                subscriptionID: nil,
                browserTabID: nil,
                browserContextID: nil,
                pageID: nil,
                frameName: nil,
                taskID: nil,
                scheduleID: nil,
                documentRevision: nil
            )).normalized().todoID == todoID
        )
        #expect(
            makeRoutingRequest(command: "events.stream.subscribe").normalized().command == "events.stream.subscribe"
        )
    }

    @Test func normalizedRequestPromotesSubscriptionTargetToStreamID() {
        let subscriptionID = UUID().uuidString
        let normalized = makeRoutingRequest(
            command: "events.stream.drain",
            target: ControlHarnessRequestTarget(
                workspaceID: nil,
                tabID: nil,
                parentTabID: nil,
                terminalID: nil,
                todoID: nil,
                subscriptionID: subscriptionID,
                browserTabID: nil,
                browserContextID: nil,
                pageID: nil,
                frameName: nil,
                taskID: nil,
                scheduleID: nil,
                documentRevision: nil
            )
        ).normalized()

        #expect(normalized.command == "events.stream.drain")
        #expect(normalized.streamID == subscriptionID)
    }

    @Test func normalizedRequestPromotesWindowAndPanelTargets() {
        let normalized = makeRoutingRequest(
            command: "panel.tab.select",
            target: ControlHarnessRequestTarget(
                workspaceID: nil,
                tabID: nil,
                parentTabID: nil,
                terminalID: nil,
                todoID: nil,
                subscriptionID: nil,
                windowNumber: 17,
                panelID: "settings",
                panelTabID: "gateway",
                browserTabID: nil,
                browserContextID: nil,
                pageID: nil,
                frameName: nil,
                taskID: nil,
                scheduleID: nil,
                documentRevision: nil
            )
        ).normalized()

        #expect(normalized.command == "panel.tab.select")
        #expect(normalized.windowNumber == 17)
        #expect(normalized.panelID == "settings")
        #expect(normalized.panelTabID == "gateway")
    }

    @Test func browserAdapterMapsRawAliasToBrowserRequest() throws {
        let request = makeRoutingRequest(
            command: "browser.loadURL",
            browserContextID: UUID().uuidString,
            pageID: UUID().uuidString,
            frameName: "main",
            documentRevision: 3,
            payload: ["url": "https://example.com"]
        )

        let browserRequest = try ControlHarnessBrowserCommandAdapter.makeRequest(from: request)
        #expect(browserRequest.command == .loadURL)
        #expect(browserRequest.version == BrowserCommandProtocolVersion.v2)
        #expect(browserRequest.browserContextID == request.browserContextID)
        #expect(browserRequest.pageID == request.pageID)
        #expect(browserRequest.frameName == "main")
        #expect(browserRequest.documentRevision == 3)
        #expect(browserRequest.payload["url"] == "https://example.com")
    }

    @Test func browserAdapterMapsProjectCanonicalCommands() throws {
        let request = makeRoutingRequest(
            command: "browser.page.navigate",
            browserTabID: UUID().uuidString,
            pageID: UUID().uuidString,
            payload: ["url": "https://example.com"]
        )

        let browserRequest = try ControlHarnessBrowserCommandAdapter.makeRequest(from: request)
        #expect(browserRequest.command == .loadURL)
        #expect(browserRequest.version == BrowserCommandProtocolVersion.v2)
        #expect(browserRequest.payload["url"] == "https://example.com")

        #expect(ControlHarnessBrowserCommandAdapter.isBrowserCommand("browser.tab.create"))
        #expect(ControlHarnessBrowserCommandAdapter.isMutation("browser.page.navigate"))
        #expect(ControlHarnessBrowserCommandAdapter.canonicalCommand(for: "browser.script.eval") == "browser.dom.eval")
    }

    @Test func commandKindClassifiesBrowserRequests() {
        let click = makeRoutingRequest(command: "browser.dom.click", payload: ["selector": "#launch"])
        let pageList = makeRoutingRequest(command: "browser.page.list")
        let eventSubscribe = makeRoutingRequest(command: "browser.event.subscribe")

        #expect(click.commandKind == .mutation)
        #expect(click.isMutation)
        #expect(pageList.commandKind == .query)
        #expect(!pageList.isMutation)
        #expect(eventSubscribe.commandKind == .query)
        #expect(ControlHarnessBrowserCommandAdapter.isResync(eventSubscribe.command))
    }

    @Test func commandKindClassifiesExpandedProtocolSurface() {
        #expect(makeRoutingRequest(command: "app.state.get").commandKind == .query)
        #expect(makeRoutingRequest(command: "window.list").commandKind == .query)
        #expect(makeRoutingRequest(command: "window.focus").commandKind == .mutation)
        #expect(makeRoutingRequest(command: "panel.list").commandKind == .query)
        #expect(makeRoutingRequest(command: "panel.open").commandKind == .mutation)
        #expect(makeRoutingRequest(command: "settings.schema.get").commandKind == .query)
        #expect(makeRoutingRequest(command: "settings.values.set").commandKind == .mutation)
        #expect(makeRoutingRequest(command: "diagnostics.metrics.get").commandKind == .query)
        #expect(makeRoutingRequest(command: "diagnostics.metrics.reset").commandKind == .mutation)
        #expect(makeRoutingRequest(command: "diagnostics.eventBuffer.status").commandKind == .query)
    }

    @Test func supportedCommandsAdvertiseUnifiedAndBrowserEntries() {
        #expect(ControlHarnessCore.supportedCommands.contains("state.snapshot"))
        #expect(ControlHarnessCore.supportedCommands.contains("system.target.resolve"))
        #expect(ControlHarnessCore.supportedCommands.contains("system.capabilities.get"))
        #expect(ControlHarnessCore.supportedCommands.contains("app.state.get"))
        #expect(ControlHarnessCore.supportedCommands.contains("window.list"))
        #expect(ControlHarnessCore.supportedCommands.contains("panel.list"))
        #expect(ControlHarnessCore.supportedCommands.contains("settings.schema.get"))
        #expect(ControlHarnessCore.supportedCommands.contains("diagnostics.metrics.get"))
        #expect(ControlHarnessCore.supportedCommands.contains("workspace.tab.snapshot"))
        #expect(ControlHarnessCore.supportedCommands.contains("terminal.write"))
        #expect(ControlHarnessCore.supportedCommands.contains("terminal.command.run"))
        #expect(ControlHarnessCore.supportedCommands.contains("runtime.task.claimNext"))
        #expect(ControlHarnessCore.supportedCommands.contains("events.stream.subscribe"))
        #expect(ControlHarnessCore.supportedCommands.contains("events.stream.drain"))
        #expect(ControlHarnessCore.supportedCommands.contains("events.stream.unsubscribe"))
        #expect(ControlHarnessCore.supportedCommands.contains("browser.page.load"))
        #expect(ControlHarnessCore.supportedCommands.contains("browser.page.navigate"))
        #expect(ControlHarnessCore.supportedCommands.contains("browser.script.eval"))
    }
}
