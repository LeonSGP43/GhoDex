import AppKit
import SwiftUI

struct BrowserTabView: View {
    @ObservedObject var model: BrowserTabModel

    var body: some View {
        VStack(spacing: 0) {
            pageTabStrip
            chromeBar

            Divider()

            Group {
                switch model.runtimeState {
                case .ready:
                    BrowserCEFDeckView(model: model)
                case .unsupportedBuild, .runtimeUnavailable, .initializationFailed:
                    BrowserRuntimeDisabledView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.pages) { page in
                    BrowserPageTabPill(
                        page: page,
                        isSelected: model.isSelected(page),
                        canClose: model.pages.count > 1,
                        onSelect: { model.selectPage(page.id) },
                        onClose: { model.closePage(page.id) })
                }

                Button(action: model.newPageTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(AppLocalization.localizedText("New Tab"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var chromeBar: some View {
        HStack(spacing: 10) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack || model.runtimeState != .ready)

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward || model.runtimeState != .ready)

            Button(action: model.reload) {
                Image(systemName: model.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
            }
            .disabled(model.runtimeState != .ready)

            TextField(
                "https://example.com",
                text: Binding(
                    get: { model.addressText },
                    set: { model.updateAddressText($0) }
                ),
                onEditingChanged: model.setAddressBarEditing(_:)
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { model.submitAddress() }

            Button(action: model.openInDefaultBrowser) {
                Image(systemName: "safari")
            }
            .help(AppLocalization.localizedText("Open in Default Browser"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct BrowserPageTabPill: View {
    @ObservedObject var page: BrowserPageState
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        BrowserPageTabPillMouseHost(onMiddleClick: canClose ? onClose : nil) {
            HStack(spacing: 8) {
                Button(action: onSelect) {
                    Text(page.tabTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                .buttonStyle(.plain)

                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture(perform: onSelect)
        }
    }
}

private struct BrowserPageTabPillMouseHost<Content: View>: NSViewRepresentable {
    let onMiddleClick: (() -> Void)?
    let content: Content

    init(onMiddleClick: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.onMiddleClick = onMiddleClick
        self.content = content()
    }

    func makeNSView(context: Context) -> BrowserPageTabPillMouseHostView {
        let view = BrowserPageTabPillMouseHostView()
        view.update(content: content, onMiddleClick: onMiddleClick)
        return view
    }

    func updateNSView(_ nsView: BrowserPageTabPillMouseHostView, context: Context) {
        nsView.update(content: content, onMiddleClick: onMiddleClick)
    }
}

private final class BrowserPageTabPillMouseHostView: NSView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var onMiddleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for BrowserPageTabPillMouseHostView")
    }

    func update<Content: View>(content: Content, onMiddleClick: (() -> Void)?) {
        hostingView.rootView = AnyView(content)
        self.onMiddleClick = onMiddleClick
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let onMiddleClick else {
            super.otherMouseDown(with: event)
            return
        }

        onMiddleClick()
    }
}

private struct BrowserRuntimeDisabledView: View {
    @ObservedObject var model: BrowserTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.localizedText("CEF Runtime Required"))
                .font(.title2.weight(.semibold))

            Text(model.runtimeFailureMessage())
                .foregroundStyle(.secondary)

            if let statusText = model.installStatusText {
                HStack(spacing: 10) {
                    if model.installPhase.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusText)
                        .foregroundStyle(model.installPhase.isWorking ? .secondary : .primary)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                if model.canInstallManagedRuntime {
                    Button(AppLocalization.localizedText("Download Browser Runtime")) {
                        model.installManagedRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(AppLocalization.localizedText("Retry")) {
                    model.retryRuntimeActivation()
                }
                .disabled(!model.canRetryRuntimeActivation)

                Button(AppLocalization.localizedText("Reveal Runtime Folder")) {
                    model.revealRuntimeFolder()
                }
                .disabled(model.installPhase.isWorking)
            }

            ForEach(Array(model.runtimeInstructions().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct BrowserCEFDeckView: NSViewRepresentable {
    @ObservedObject var model: BrowserTabModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> BrowserCEFDeckHostView {
        BrowserCEFDeckHostView()
    }

    func updateNSView(_ nsView: BrowserCEFDeckHostView, context: Context) {
        context.coordinator.sync(
            into: nsView,
            pages: model.pages,
            selectedPageID: model.selectedPageID,
            visiblePageIDs: model.visiblePageIDsInDeck,
            splitAxis: model.splitAxis
        )
    }

    static func dismantleNSView(_ nsView: BrowserCEFDeckHostView, coordinator: Coordinator) {
        coordinator.reset(from: nsView)
    }

    @MainActor
    final class Coordinator {
        private let model: BrowserTabModel
        private var views: [UUID: GhoDexCEFView] = [:]
        private var delegates: [UUID: PageDelegate] = [:]

        init(model: BrowserTabModel) {
            self.model = model
        }

        func sync(
            into host: BrowserCEFDeckHostView,
            pages: [BrowserPageState],
            selectedPageID: UUID,
            visiblePageIDs: [UUID],
            splitAxis: BrowserDeckSplitAxis
        ) {
            let validIDs = Set(pages.map(\.id))
            var removedIDs: [String] = []
            for id in views.keys where !validIDs.contains(id) {
                if let view = views.removeValue(forKey: id) {
                    view.delegate = nil
                    view.removeFromSuperview()
                }
                delegates.removeValue(forKey: id)
                model.unbindBridge(for: id)
                removedIDs.append(id.uuidString)
            }

            var createdIDs: [String] = []
            for page in pages {
                let isNewView = views[page.id] == nil
                let view = view(for: page)
                if isNewView {
                    createdIDs.append(page.id.uuidString)
                }
                if view.superview !== host {
                    host.addManagedSubview(view)
                }
                view.isHidden = !visiblePageIDs.contains(page.id)
            }

            let arrangedViews = visiblePageIDs.compactMap { views[$0] }
            let effectiveAxis: BrowserDeckSplitAxis? = arrangedViews.count >= 2 ? splitAxis : nil
            host.configureLayout(views: arrangedViews, splitAxis: effectiveAxis)
            host.needsLayout = true

            if !createdIDs.isEmpty || !removedIDs.isEmpty {
                logDeckEvent(
                    "deck_sync_structure_changed",
                    details: [
                        "selected_page_id": selectedPageID.uuidString,
                        "page_count": "\(pages.count)",
                        "visible_page_ids": visiblePageIDs.map(\.uuidString).joined(separator: ","),
                        "split_axis": splitAxis.rawValue,
                        "created_page_ids": createdIDs.joined(separator: ","),
                        "removed_page_ids": removedIDs.joined(separator: ","),
                    ]
                )
            }
        }

        func reset(from host: BrowserCEFDeckHostView) {
            let removedIDs = views.keys.map(\.uuidString).sorted().joined(separator: ",")
            for (id, view) in views {
                view.delegate = nil
                view.removeFromSuperview()
                model.unbindBridge(for: id)
            }
            views.removeAll()
            delegates.removeAll()
            host.subviews.forEach { $0.removeFromSuperview() }
            logDeckEvent(
                "deck_reset",
                details: [
                    "removed_page_ids": removedIDs,
                ]
            )
        }

        private func view(for page: BrowserPageState) -> GhoDexCEFView {
            if let existing = views[page.id] {
                return existing
            }

            let view = GhoDexCEFView(initialURLString: page.initialURL.absoluteString)
            let delegate = PageDelegate(model: model, pageID: page.id)
            view.delegate = delegate
            delegates[page.id] = delegate
            views[page.id] = view
            model.bindBridge(for: page.id, bridge: makeControlBridge(for: page.id, view: view))
            logDeckEvent(
                "deck_view_created",
                details: [
                    "page_id": page.id.uuidString,
                    "initial_url": page.initialURL.absoluteString,
                ]
            )
            return view
        }

        private func logDeckEvent(_ event: String, details: [String: String]) {
            RuntimeDiagnosticsLogger.log(
                component: "browser.deck",
                event: event,
                details: details
            )
        }

        private func makeControlBridge(for pageID: UUID, view: GhoDexCEFView) -> BrowserPageControlBridge {
            BrowserPageControlBridge(dispatch: { [weak view] request, completion in
                guard let view else {
                    completion(.failure(
                        for: request,
                        error: .bridgeUnavailable("The browser view for page \(pageID) is no longer available.")
                    ))
                    return
                }

                switch request.command {
                case .loadURL:
                    guard let url = request.payload["url"], !url.isEmpty else {
                        completion(.failure(
                            for: request,
                            error: .invalidRequest("The loadURL command requires a non-empty url payload.")
                        ))
                        return
                    }
                    self.model.markBridgePending(for: pageID)
                    completion(.success(for: request))
                    // Schedule navigation after the IPC reply is released so
                    // reentrant auth/certificate prompts cannot strand the
                    // original loadURL request on the control socket.
                    DispatchQueue.main.async {
                        view.loadURLString(url)
                    }
                case .goBack:
                    self.model.markBridgePending(for: pageID)
                    view.goBack()
                    completion(.success(for: request))
                case .goForward:
                    self.model.markBridgePending(for: pageID)
                    view.goForward()
                    completion(.success(for: request))
                case .reload:
                    self.model.markBridgePending(for: pageID)
                    view.reloadPage()
                    completion(.success(for: request))
                case .cancelDownload:
                    self.routeDownloadControlCommand(
                        request,
                        pageID: pageID,
                        view: view,
                        completion: completion
                    )
                case .resolveDialog,
                     .resolvePermission,
                     .resolveAuth,
                     .resolveCertificate:
                    self.routeRuntimePromptResolutionCommand(
                        request,
                        pageID: pageID,
                        view: view,
                        completion: completion
                    )
                case .executeJavaScript:
                    guard let script = request.payload["script"], !script.isEmpty else {
                        completion(.failure(
                            for: request,
                            error: .invalidRequest("The executeJavaScript command requires a script payload.")
                        ))
                        return
                    }
                    view.executeJavaScript(script, frameName: request.target.frameName)
                    completion(.success(for: request))
                case .evaluateJavaScript:
                    guard let script = request.payload["script"], !script.isEmpty else {
                        completion(.failure(
                            for: request,
                            error: .invalidRequest("The evaluateJavaScript command requires a script payload.")
                        ))
                        return
                    }
                    view.evaluateJavaScript(script, frameName: request.target.frameName) { resultJSON, error in
                        if let error {
                            completion(.failure(
                                for: request,
                                error: .internalFailure(error.localizedDescription)
                            ))
                            return
                        }

                        completion(.success(for: request, valueJSON: resultJSON))
                    }
                case .listFrames:
                    view.listFrames { resultJSON, error in
                        if let error {
                            completion(.failure(
                                for: request,
                                error: .internalFailure(error.localizedDescription)
                            ))
                            return
                        }

                        completion(.success(for: request, valueJSON: resultJSON))
                    }
                case .query,
                     .click,
                     .typeText,
                     .waitForSelector,
                     .getDOMSnapshot,
                     .getText,
                     .getAttributes,
                     .getBoundingBox,
                     .batchDOMCommands:
                    self.routeDOMCommand(request, pageID: pageID, view: view, completion: completion)
                }
            })
        }

        private func routeDownloadControlCommand(
            _ request: BrowserControlRequest,
            pageID: UUID,
            view: GhoDexCEFView,
            completion: @escaping BrowserControlCompletion
        ) {
            let downloadID = request.payload["downloadID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !downloadID.isEmpty else {
                completion(.failure(
                    for: request,
                    error: .invalidRequest("The download control command requires a non-empty downloadID payload.")
                ))
                return
            }

            do {
                switch request.command {
                case .cancelDownload:
                    try view.cancelDownloadID(downloadID)
                default:
                    completion(.failure(
                        for: request,
                        error: .commandUnsupported("The browser download control command \(request.command.rawValue) is not supported by the Browser bridge.")
                    ))
                    return
                }

                completion(.success(for: request))
            } catch {
                completion(.failure(
                    for: request,
                    error: downloadControlError(
                        error as NSError,
                        downloadID: downloadID,
                        command: request.command,
                        pageID: pageID
                    )
                ))
            }
        }

        private func downloadControlError(
            _ error: NSError?,
            downloadID: String,
            command: BrowserControlCommandKind,
            pageID: UUID
        ) -> BrowserControlError {
            guard let error else {
                return .internalFailure(
                    "The browser download \(downloadID) on page \(pageID) could not be resolved for \(command.rawValue)."
                )
            }

            if error.domain == GhoDexCEFControlErrorDomain {
                if error.code == 5 {
                    return .invalidRequest(error.localizedDescription)
                }
                if error.code == 1 {
                    return .bridgeUnavailable(error.localizedDescription)
                }
            }

            return .internalFailure(error.localizedDescription)
        }

        private func routeRuntimePromptResolutionCommand(
            _ request: BrowserControlRequest,
            pageID: UUID,
            view: GhoDexCEFView,
            completion: @escaping BrowserControlCompletion
        ) {
            let requestID = request.payload["requestID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !requestID.isEmpty else {
                completion(.failure(
                    for: request,
                    error: .invalidRequest("The runtime prompt resolution command requires a non-empty requestID payload.")
                ))
                return
            }

            do {
                switch request.command {
                case .resolveDialog:
                    let accepted = request.payload["accepted"] == "true"
                    try view.resolveDialogRequestID(
                        requestID,
                        accepted: accepted,
                        userInput: request.payload["userInput"]
                    )
                case .resolvePermission:
                    let result = request.payload["result"] ?? ""
                    try view.resolvePermissionRequestID(
                        requestID,
                        result: result
                    )
                case .resolveAuth:
                    let accepted = request.payload["accepted"] == "true"
                    try view.resolveAuthRequestID(
                        requestID,
                        accepted: accepted,
                        username: request.payload["username"],
                        password: request.payload["password"]
                    )
                case .resolveCertificate:
                    let accepted = request.payload["accepted"] == "true"
                    try view.resolveCertificateRequestID(
                        requestID,
                        accepted: accepted
                    )
                default:
                    completion(.failure(
                        for: request,
                        error: .commandUnsupported("The browser runtime prompt command \(request.command.rawValue) is not supported by the Browser bridge.")
                    ))
                    return
                }

                completion(.success(for: request))
                return
            } catch {
                let resolvedError = runtimePromptResolutionError(
                    error as NSError,
                    requestID: requestID,
                    command: request.command,
                    pageID: pageID
                )
                completion(.failure(for: request, error: resolvedError))
                return
            }
        }

        private func runtimePromptResolutionError(
            _ error: NSError?,
            requestID: String,
            command: BrowserControlCommandKind,
            pageID: UUID
        ) -> BrowserControlError {
            guard let error else {
                return .internalFailure(
                    "The browser runtime prompt \(requestID) on page \(pageID) could not be resolved for \(command.rawValue)."
                )
            }

            if error.domain == GhoDexCEFControlErrorDomain {
                if error.code == 4 {
                    return .invalidRequest(error.localizedDescription)
                }
                if error.code == 1 {
                    return .bridgeUnavailable(error.localizedDescription)
                }
            }

            return .internalFailure(error.localizedDescription)
        }

        private func routeDOMCommand(
            _ request: BrowserControlRequest,
            pageID: UUID,
            view: GhoDexCEFView,
            completion: @escaping BrowserControlCompletion
        ) {
            if request.command == .click {
                routeClickCommand(request, pageID: pageID, view: view, completion: completion)
                return
            }

            let script: String
            do {
                script = try BrowserControlScriptBuilder.script(for: request)
            } catch let error as BrowserControlScriptBuilderError {
                completion(.failure(for: request, error: .invalidRequest(error.localizedDescription)))
                return
            } catch {
                completion(.failure(for: request, error: .internalFailure(error.localizedDescription)))
                return
            }

            view.evaluateJavaScript(script, frameName: request.target.frameName) { resultJSON, error in
                if let error {
                    completion(.failure(
                        for: request,
                        error: .internalFailure(error.localizedDescription)
                    ))
                    return
                }

                completion(.success(for: request, valueJSON: resultJSON))
            }
        }

        private func routeClickCommand(
            _ request: BrowserControlRequest,
            pageID: UUID,
            view: GhoDexCEFView,
            completion: @escaping BrowserControlCompletion
        ) {
            guard let selector = request.payload["selector"], !selector.isEmpty else {
                completion(.failure(
                    for: request,
                    error: .invalidRequest("The click command requires a non-empty selector payload.")
                ))
                return
            }

            let clickMode = (request.payload["clickMode"] ?? "auto").lowercased()
            let prefersTrustedClick = clickMode == "auto" || clickMode == "trusted"
            let shouldFallbackToDOM = clickMode == "auto"

            guard clickMode == "auto" || clickMode == "trusted" || clickMode == "dom" else {
                completion(.failure(
                    for: request,
                    error: .invalidRequest("The clickMode payload must be one of auto, trusted, or dom.")
                ))
                return
            }

            if clickMode == "dom" {
                routeDOMClickCommand(
                    request,
                    selector: selector,
                    view: view,
                    fallbackUsed: false,
                    completion: completion
                )
                return
            }

            if pageID != model.selectedPageID {
                if let currentlySelectedView = views[model.selectedPageID] {
                    currentlySelectedView.isHidden = true
                }
                model.selectPage(pageID)
                view.isHidden = false
                view.superview?.layoutSubtreeIfNeeded()
            }

            if request.target.frameName != nil {
                if shouldFallbackToDOM {
                    routeDOMClickCommand(
                        request,
                        selector: selector,
                        view: view,
                        fallbackUsed: true,
                        completion: completion
                    )
                    return
                }

                completion(.failure(
                    for: request,
                    error: .invalidRequest("Trusted click currently supports only the main frame. Omit frameName or use clickMode=dom.")
                ))
                return
            }

            guard prefersTrustedClick else {
                routeDOMClickCommand(
                    request,
                    selector: selector,
                    view: view,
                    fallbackUsed: false,
                    completion: completion
                )
                return
            }

            let targetScript: String
            do {
                targetScript = try BrowserControlScriptBuilder.trustedClickTargetScript(selector: selector)
            } catch let error as BrowserControlScriptBuilderError {
                completion(.failure(for: request, error: .invalidRequest(error.localizedDescription)))
                return
            } catch {
                completion(.failure(for: request, error: .internalFailure(error.localizedDescription)))
                return
            }

            view.evaluateJavaScript(targetScript, frameName: nil) { resultJSON, error in
                if let error {
                    if shouldFallbackToDOM {
                        self.routeDOMClickCommand(
                            request,
                            selector: selector,
                            view: view,
                            fallbackUsed: true,
                            completion: completion
                        )
                        return
                    }

                    completion(.failure(
                        for: request,
                        error: .internalFailure(error.localizedDescription)
                    ))
                    return
                }

                guard
                    let resultJSON,
                    let data = resultJSON.data(using: .utf8),
                    let target = try? JSONDecoder().decode(BrowserTrustedClickTargetResult.self, from: data),
                    target.found,
                    let centerX = target.centerX,
                    let centerY = target.centerY
                else {
                    if shouldFallbackToDOM {
                        self.routeDOMClickCommand(
                            request,
                            selector: selector,
                            view: view,
                            fallbackUsed: true,
                            completion: completion
                        )
                        return
                    }

                    completion(.failure(
                        for: request,
                        error: .internalFailure("The browser could not resolve a trusted click target.")
                    ))
                    return
                }

                do {
                    try view.performTrustedClickAt(x: centerX, y: centerY)
                    let result = BrowserDOMClickResult(
                        clicked: true,
                        selector: selector,
                        trusted: true,
                        transport: "native",
                        fallbackUsed: false
                    )
                    let encoded = try JSONEncoder().encode(result)
                    completion(.success(for: request, valueJSON: String(bytes: encoded, encoding: .utf8)))
                } catch {
                    if shouldFallbackToDOM {
                        self.routeDOMClickCommand(
                            request,
                            selector: selector,
                            view: view,
                            fallbackUsed: true,
                            completion: completion
                        )
                        return
                    }

                    completion(.failure(
                        for: request,
                        error: .internalFailure(error.localizedDescription)
                    ))
                }
            }
        }

        private func routeDOMClickCommand(
            _ request: BrowserControlRequest,
            selector: String,
            view: GhoDexCEFView,
            fallbackUsed: Bool,
            completion: @escaping BrowserControlCompletion
        ) {
            let script: String
            do {
                script = try BrowserControlScriptBuilder.script(for: request)
            } catch let error as BrowserControlScriptBuilderError {
                completion(.failure(for: request, error: .invalidRequest(error.localizedDescription)))
                return
            } catch {
                completion(.failure(for: request, error: .internalFailure(error.localizedDescription)))
                return
            }

            view.evaluateJavaScript(script, frameName: request.target.frameName) { resultJSON, error in
                if let error {
                    completion(.failure(
                        for: request,
                        error: .internalFailure(error.localizedDescription)
                    ))
                    return
                }

                guard
                    let resultJSON,
                    let data = resultJSON.data(using: .utf8),
                    let rawResult = try? JSONDecoder().decode(BrowserDOMClickResult.self, from: data)
                else {
                    completion(.failure(
                        for: request,
                        error: .internalFailure("The browser returned an invalid DOM click result.")
                    ))
                    return
                }

                let normalizedResult = BrowserDOMClickResult(
                    clicked: rawResult.clicked,
                    selector: rawResult.selector.isEmpty ? selector : rawResult.selector,
                    trusted: false,
                    transport: "dom",
                    fallbackUsed: fallbackUsed
                )

                do {
                    let encoded = try JSONEncoder().encode(normalizedResult)
                    completion(.success(for: request, valueJSON: String(bytes: encoded, encoding: .utf8)))
                } catch {
                    completion(.failure(
                        for: request,
                        error: .internalFailure(error.localizedDescription)
                    ))
                }
            }
        }
    }
}

@MainActor
private final class PageDelegate: NSObject, @preconcurrency GhoDexCEFViewDelegate {
    private let model: BrowserTabModel
    private let pageID: UUID

    init(model: BrowserTabModel, pageID: UUID) {
        self.model = model
        self.pageID = pageID
    }

    func cefViewDidBecomeReady(_ view: GhoDexCEFView) {
        guard let target = model.controlTarget(for: pageID) else { return }
        model.handle(.bridgeReady(target: target, url: model.pageNavigationState(for: pageID).url), from: pageID)
    }

    func cefView(_ view: GhoDexCEFView, didUpdateTitle title: String) {
        guard let target = model.controlTarget(for: pageID) else { return }
        model.handle(.pageTitleChanged(target: target, title: title), from: pageID)
    }

    func cefView(
        _ view: GhoDexCEFView,
        didUpdateURL url: String,
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        model.handle(
            .navigationStateChanged(
                target: target,
                url: url,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                isLoading: isLoading
            ),
            from: pageID
        )
    }

    func cefView(
        _ view: GhoDexCEFView,
        didReceiveConsoleMessage message: String,
        level: String,
        source: String,
        line: NSInteger
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        model.handle(
            .consoleMessage(
                target: target,
                level: level,
                message: message,
                source: source,
                line: Int(line)
            ),
            from: pageID
        )
    }

    // swiftlint:disable:next function_parameter_count
    func cefView(
        _ view: GhoDexCEFView,
        didFinishNetworkRequestForURL url: String,
        method: String,
        requestStatus: String,
        statusCode: NSInteger,
        statusText: String,
        mimeType: String,
        receivedContentLength: Int64,
        isMainFrame: Bool,
        frameName: String
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        model.handle(
            .networkRequestFinished(
                target: target,
                url: url,
                method: method,
                requestStatus: requestStatus,
                statusCode: Int(statusCode),
                statusText: statusText,
                mimeType: mimeType,
                receivedContentLength: receivedContentLength,
                isMainFrame: isMainFrame,
                frameName: frameName
            ),
            from: pageID
        )
    }

    func cefView(
        _ view: GhoDexCEFView,
        requestOpenURLInNewTab urlString: String,
        disposition: NSInteger,
        userGesture: Bool
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        let resolvedDisposition = BrowserPopupDisposition(rawValue: Int(disposition)) ?? .newForegroundTab
        model.handle(
            .openURLInNewTabRequested(
                target: target,
                url: urlString,
                disposition: resolvedDisposition,
                userGesture: userGesture
            ),
            from: pageID
        )
    }

    func cefView(
        _ view: GhoDexCEFView,
        didHostPopupWindowForURL urlString: String,
        disposition: NSInteger,
        userGesture: Bool
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        let resolvedDisposition = BrowserPopupDisposition(rawValue: Int(disposition)) ?? .newPopup
        model.handle(
            .popupWindowHosted(
                target: target,
                url: urlString,
                disposition: resolvedDisposition,
                userGesture: userGesture
            ),
            from: pageID
        )
    }

    func cefView(
        _ view: GhoDexCEFView,
        didEmitRuntimeEventKind kind: String,
        payload: [String: String]
    ) {
        guard let target = model.controlTarget(for: pageID) else { return }
        guard let eventKind = BrowserControlEventKind(rawValue: kind) else { return }
        model.handle(BrowserControlEvent(target: target, kind: eventKind, payload: payload), from: pageID)
    }
}

@MainActor
private final class BrowserCEFDeckHostView: NSView {
    private var arrangedViews: [NSView] = []
    private var splitAxis: BrowserDeckSplitAxis?

    override func layout() {
        super.layout()

        guard arrangedViews.count >= 2, let splitAxis else {
            for subview in subviews where !subview.isHidden {
                subview.frame = bounds
            }
            return
        }

        let primaryView = arrangedViews[0]
        let secondaryView = arrangedViews[1]
        let divider: CGFloat = 1

        switch splitAxis {
        case .vertical:
            let primaryWidth = floor((bounds.width - divider) * 0.5)
            primaryView.frame = NSRect(x: 0, y: 0, width: primaryWidth, height: bounds.height)
            secondaryView.frame = NSRect(
                x: primaryWidth + divider,
                y: 0,
                width: max(0, bounds.width - primaryWidth - divider),
                height: bounds.height
            )
        case .horizontal:
            let secondaryHeight = floor((bounds.height - divider) * 0.5)
            secondaryView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: secondaryHeight)
            primaryView.frame = NSRect(
                x: 0,
                y: secondaryHeight + divider,
                width: bounds.width,
                height: max(0, bounds.height - secondaryHeight - divider)
            )
        }
    }

    func addManagedSubview(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    func configureLayout(views: [NSView], splitAxis: BrowserDeckSplitAxis?) {
        self.arrangedViews = views
        self.splitAxis = splitAxis
    }
}
