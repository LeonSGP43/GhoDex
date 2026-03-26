import Foundation
import Testing
@testable import GhoDex

@MainActor
struct BrowserPopupEventTests {
    @Test func popupRequestEventIncludesResolvedPageTabOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        var receivedEvent: BrowserControlEvent?

        let token = model.subscribeToControlEvents(kinds: [.openURLInNewTabRequested]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .openURLInNewTabRequested(
                target: sourceTarget,
                url: "https://popup.example/child",
                disposition: .newForegroundTab,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["sourcePageID"] == sourcePageID.uuidString)
        #expect(event.payload["requestedURL"] == "https://popup.example/child")
        #expect(event.payload["dispositionName"] == "newForegroundTab")
        #expect(event.payload["routingTarget"] == "pageTab")
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "foreground")

        let resultPageID = try #require(event.payload["resultPageID"]).lowercased()
        #expect(model.selectedPageID.uuidString.lowercased() == resultPageID)
        #expect(model.pages.contains { $0.id.uuidString.lowercased() == resultPageID })
    }

    @Test func popupRequestEventIncludesResolvedBrowserWindowOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        let destinationPageID = UUID()
        var receivedEvent: BrowserControlEvent?

        model.openURLInNewWindowHandler = { _ in
            BrowserPopupOpenWindowResult(
                browserTabID: "browser-tab-popup-target",
                pageID: destinationPageID,
                isPageActive: true,
                visibilityState: "newWindowRequested"
            )
        }

        let token = model.subscribeToControlEvents(kinds: [.openURLInNewTabRequested]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .openURLInNewTabRequested(
                target: sourceTarget,
                url: "https://popup.example/window",
                disposition: .newWindow,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["routingTarget"] == "browserWindow")
        #expect(event.payload["resultBrowserTabID"] == "browser-tab-popup-target")
        #expect(event.payload["resultPageID"] == destinationPageID.uuidString)
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "newWindowRequested")
    }

    @Test func popupRequestEventIncludesDedicatedPopupHostOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        var receivedEvent: BrowserControlEvent?

        let token = model.subscribeToControlEvents(kinds: [.popupWindowHosted]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .popupWindowHosted(
                target: sourceTarget,
                url: "https://popup.example/dedicated",
                disposition: .newPopup,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["sourcePageID"] == sourcePageID.uuidString)
        #expect(event.payload["requestedURL"] == "https://popup.example/dedicated")
        #expect(event.payload["dispositionName"] == "newPopup")
        #expect(event.payload["routingTarget"] == "popupWindowHost")
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "popupWindowForeground")
        #expect(event.payload["resultPageID"] == nil)
        #expect(event.payload["resultBrowserTabID"] == nil)
    }
}

@MainActor
struct BrowserRuntimeServiceEventTests {
    @Test func runtimeServiceEventKindsMapToTheExternalBrokerSurface() {
        let observedKinds = BrowserExternalEventBroker.observedControlKinds(
            for: [.download, .javaScriptDialog, .permissionRequest, .authenticationRequest, .certificateWarning]
        )

        #expect(observedKinds.contains(.download))
        #expect(observedKinds.contains(.javaScriptDialog))
        #expect(observedKinds.contains(.permissionRequest))
        #expect(observedKinds.contains(.authenticationRequest))
        #expect(observedKinds.contains(.certificateWarning))

        #expect(BrowserExternalEventBroker.externalEventKind(for: .download) == .download)
        #expect(BrowserExternalEventBroker.externalEventKind(for: .javaScriptDialog) == .javaScriptDialog)
        #expect(BrowserExternalEventBroker.externalEventKind(for: .permissionRequest) == .permissionRequest)
        #expect(BrowserExternalEventBroker.externalEventKind(for: .authenticationRequest) == .authenticationRequest)
        #expect(BrowserExternalEventBroker.externalEventKind(for: .certificateWarning) == .certificateWarning)
    }

    @Test func runtimeServiceEventPayloadFactoriesPreserveStableFields() {
        let target = BrowserControlTarget(pageID: UUID(), documentRevision: 7)

        let downloadEvent = BrowserControlEvent.download(
            target: target,
            phase: "started",
            downloadID: "41",
            url: "https://example.com/file.zip",
            suggestedName: "file.zip",
            targetPath: "/Users/test/Downloads/file.zip",
            mimeType: "application/zip",
            receivedBytes: 0,
            totalBytes: 1024,
            percentComplete: 0,
            isComplete: false,
            isCanceled: false,
            isInterrupted: false
        )
        #expect(downloadEvent.kind == .download)
        #expect(downloadEvent.payload["phase"] == "started")
        #expect(downloadEvent.payload["downloadID"] == "41")
        #expect(downloadEvent.payload["targetPath"] == "/Users/test/Downloads/file.zip")

        let dialogEvent = BrowserControlEvent.javaScriptDialog(
            target: target,
            requestID: "dialog-1",
            phase: "resolved",
            dialogType: "prompt",
            originURL: "https://example.com",
            messageText: "Name?",
            defaultPromptText: "anon",
            isReload: nil,
            accepted: true,
            userInput: "leon"
        )
        #expect(dialogEvent.kind == .javaScriptDialog)
        #expect(dialogEvent.payload["requestID"] == "dialog-1")
        #expect(dialogEvent.payload["phase"] == "resolved")
        #expect(dialogEvent.payload["dialogType"] == "prompt")
        #expect(dialogEvent.payload["accepted"] == "true")
        #expect(dialogEvent.payload["userInput"] == "leon")

        let permissionEvent = BrowserControlEvent.permissionRequest(
            target: target,
            requestID: "perm-1",
            phase: "resolved",
            permissionKind: "generic",
            originURL: "https://example.com",
            requestedPermissions: "camera,microphone",
            requestedPermissionsLabel: "camera, microphone",
            promptID: "9",
            result: "allow"
        )
        #expect(permissionEvent.kind == .permissionRequest)
        #expect(permissionEvent.payload["requestID"] == "perm-1")
        #expect(permissionEvent.payload["promptID"] == "9")
        #expect(permissionEvent.payload["result"] == "allow")

        let authEvent = BrowserControlEvent.authenticationRequest(
            target: target,
            requestID: "auth-1",
            phase: "requested",
            originURL: "https://example.com",
            host: "example.com",
            port: 443,
            realm: "Members",
            scheme: "basic",
            isProxy: false,
            accepted: nil
        )
        #expect(authEvent.kind == .authenticationRequest)
        #expect(authEvent.payload["requestID"] == "auth-1")
        #expect(authEvent.payload["host"] == "example.com")
        #expect(authEvent.payload["isProxy"] == "false")

        let certificateEvent = BrowserControlEvent.certificateWarning(
            target: target,
            requestID: "cert-1",
            phase: "resolved",
            requestURL: "https://expired.example.com",
            errorCode: "-202",
            accepted: false
        )
        #expect(certificateEvent.kind == .certificateWarning)
        #expect(certificateEvent.payload["requestID"] == "cert-1")
        #expect(certificateEvent.payload["requestURL"] == "https://expired.example.com")
        #expect(certificateEvent.payload["accepted"] == "false")
    }

    @Test func runtimeServiceEventsPassThroughTheBrowserModelObserverPath() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        var receivedEvent: BrowserControlEvent?

        let token = model.subscribeToControlEvents(kinds: [.certificateWarning]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .certificateWarning(
                target: sourceTarget,
                requestID: "cert-live-1",
                phase: "requested",
                requestURL: "https://expired.example.com",
                errorCode: "-202",
                accepted: nil
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.kind == .certificateWarning)
        #expect(event.payload["requestID"] == "cert-live-1")
        #expect(event.payload["phase"] == "requested")
        #expect(event.payload["requestURL"] == "https://expired.example.com")
        #expect(model.pages.count == 1)
        #expect(model.selectedPageID == sourcePageID)
    }
}

struct BrowserPromptResolutionTests {
    @Test func dialogResolutionRequestParsesRequiredFields() throws {
        let request = try BrowserRuntimePromptResolutionRequest.dialog(
            from: [
                "requestID": "dialog-42",
                "accepted": "true",
                "userInput": "Leon",
            ]
        )

        #expect(request.requestID == "dialog-42")
        #expect(request.kind == .dialog)
        #expect(request.accepted == true)
        #expect(request.userInput == "Leon")
    }

    @Test func permissionResolutionRequestParsesAllowedResults() throws {
        let request = try BrowserRuntimePromptResolutionRequest.permission(
            from: [
                "requestID": "perm-9",
                "result": "dismiss",
            ]
        )

        #expect(request.requestID == "perm-9")
        #expect(request.kind == .permission)
        #expect(request.result == "dismiss")
    }

    @Test func authResolutionRequestParsesCredentialPayload() throws {
        let request = try BrowserRuntimePromptResolutionRequest.auth(
            from: [
                "requestID": "auth-7",
                "accepted": "true",
                "username": "demo",
                "password": "secret",
            ]
        )

        #expect(request.requestID == "auth-7")
        #expect(request.kind == .auth)
        #expect(request.accepted == true)
        #expect(request.username == "demo")
        #expect(request.password == "secret")
    }

    @Test func certificateResolutionRequestRequiresBooleanAccepted() {
        do {
            _ = try BrowserRuntimePromptResolutionRequest.certificate(
                from: [
                    "requestID": "cert-5",
                    "accepted": "later",
                ]
            )
            Issue.record("Expected invalid boolean payload to throw")
        } catch let error as BrowserExternalCommandError {
            #expect(error.code == "invalid_request")
            #expect(error.message == "The accepted payload must be true or false.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func permissionResolutionRequestRejectsUnknownResult() {
        do {
            _ = try BrowserRuntimePromptResolutionRequest.permission(
                from: [
                    "requestID": "perm-10",
                    "result": "maybe",
                ]
            )
            Issue.record("Expected invalid permission result to throw")
        } catch let error as BrowserExternalCommandError {
            #expect(error.code == "invalid_request")
            #expect(
                error.message
                    == "The resolvePermission command requires result to be one of allow, deny, or dismiss."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func runtimeResolutionAckPreservesStableShape() throws {
        let ack = BrowserExternalRuntimeResolutionAck(
            requestID: "auth-99",
            kind: .auth,
            resolved: true
        )

        let data = try JSONEncoder().encode(ack)
        let decoded = try JSONDecoder().decode(BrowserExternalRuntimeResolutionAck.self, from: data)

        #expect(decoded.requestID == "auth-99")
        #expect(decoded.kind == .auth)
        #expect(decoded.resolved == true)
    }
}
