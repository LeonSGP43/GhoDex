import SwiftUI
import AppKit
import Combine

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)

    struct Resize {
        let node: SplitTree<TerminalPane>.Node
        let ratio: Double
    }

    struct Drop {
        /// The surface being dragged.
        let payload: Ghostty.SurfaceView

        /// The surface it was dragged onto
        let destination: Ghostty.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<TerminalPane>
    let action: (TerminalSplitOperation) -> Void
    let onFocusPane: (TerminalPane) -> Void
    let onSelectPaneTab: (TerminalPane, UUID) -> Void
    let onNewPaneTab: (TerminalPane) -> Void
    let onClosePaneTab: (TerminalPane, UUID) -> Void

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            TerminalSplitSubtreeView(
                node: node,
                isRoot: node == tree.root,
                action: action,
                onFocusPane: onFocusPane,
                onSelectPaneTab: onSelectPaneTab,
                onNewPaneTab: onNewPaneTab,
                onClosePaneTab: onClosePaneTab)
            // This is necessary because we can't rely on SwiftUI's implicit
            // structural identity to detect changes to this view. Due to
            // the tree structure of splits it could result in bad behaviors.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var ghostty: Ghostty.App

    let node: SplitTree<TerminalPane>.Node
    var isRoot: Bool = false
    let action: (TerminalSplitOperation) -> Void
    let onFocusPane: (TerminalPane) -> Void
    let onSelectPaneTab: (TerminalPane, UUID) -> Void
    let onNewPaneTab: (TerminalPane) -> Void
    let onClosePaneTab: (TerminalPane, UUID) -> Void

    var body: some View {
        switch node {
        case .leaf(let pane):
            TerminalSplitLeaf(
                pane: pane,
                isSplit: !isRoot,
                action: action,
                onFocusPane: onFocusPane,
                onSelectPaneTab: onSelectPaneTab,
                onNewPaneTab: onNewPaneTab,
                onClosePaneTab: onClosePaneTab)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    TerminalSplitSubtreeView(
                        node: split.left,
                        action: action,
                        onFocusPane: onFocusPane,
                        onSelectPaneTab: onSelectPaneTab,
                        onNewPaneTab: onNewPaneTab,
                        onClosePaneTab: onClosePaneTab)
                },
                right: {
                    TerminalSplitSubtreeView(
                        node: split.right,
                        action: action,
                        onFocusPane: onFocusPane,
                        onSelectPaneTab: onSelectPaneTab,
                        onNewPaneTab: onNewPaneTab,
                        onClosePaneTab: onClosePaneTab)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().activeSurface.surface else { return }
                    ghostty.splitEqualize(surface: surface)
                }
            )
        }
    }
}

private struct TerminalSplitLeaf: View {
    @EnvironmentObject var ghostty: Ghostty.App

    @ObservedObject var pane: TerminalPane
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void
    let onFocusPane: (TerminalPane) -> Void
    let onSelectPaneTab: (TerminalPane, UUID) -> Void
    let onNewPaneTab: (TerminalPane) -> Void
    let onClosePaneTab: (TerminalPane, UUID) -> Void

    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            paneContent
                .background {
                    // If we're dragging ourself, we hide the entire drop zone. This makes
                    // it so that a released drop animates back to its source properly
                    // so it is a proper invalid drop zone.
                    if !isSelfDragging {
                        Color.clear
                            .onDrop(of: [.ghosttySurfaceId], delegate: SplitDropDelegate(
                                dropState: $dropState,
                                viewSize: geometry.size,
                                destinationSurface: activePaneView,
                                action: action
                            ))
                    }
                }
                .overlay {
                    if !isSelfDragging, case .dropping(let zone) = dropState {
                        zone.overlay(in: geometry)
                            .allowsHitTesting(false)
                    }
                }
                .onPreferenceChange(Ghostty.DraggingSurfaceKey.self) { value in
                    isSelfDragging = value == activePaneView.id
                    if isSelfDragging {
                        dropState = .idle
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(AppLocalization.localizedText("Terminal pane"))
        }
    }

    private var paneTabViews: [Ghostty.SurfaceView] {
        let tabs = pane.surfaces
        return tabs.isEmpty ? [pane.activeSurface] : tabs
    }

    private var activePaneView: Ghostty.SurfaceView {
        pane.activeSurface
    }

    private var showsPaneStrip: Bool {
        isSplit || paneTabViews.count > 1
    }

    @ViewBuilder
    private var paneContent: some View {
        if showsPaneStrip {
            VStack(spacing: 0) {
                TerminalPaneTabStrip(
                    tabs: paneTabViews,
                    activeID: activePaneView.id,
                    showsCloseButtons: paneTabViews.count > 1,
                    onFocus: { onFocusPane(pane) },
                    onSelect: { onSelectPaneTab(pane, $0) },
                    onNew: { onNewPaneTab(pane) },
                    onClose: { onClosePaneTab(pane, $0) })
                    .frame(height: 32)

                Ghostty.InspectableSurface(
                    surfaceView: activePaneView,
                    isSplit: isSplit)
                    .id(activePaneView.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        } else {
            Ghostty.InspectableSurface(
                surfaceView: activePaneView,
                isSplit: isSplit)
                .id(activePaneView.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: Ghostty.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.ghosttySurfaceId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            dropState = .idle

            // Load the dropped surface asynchronously using Transferable
            let providers = info.itemProviders(for: [.ghosttySurfaceId])
            guard let provider = providers.first else { return false }

            // Capture action before the async closure
            _ = provider.loadTransferable(type: Ghostty.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Don't allow dropping on self
                        guard let destinationSurface else { return }
                        guard sourceSurface !== destinationSurface else { return }
                        action(.drop(.init(payload: sourceSurface, destination: destinationSurface, zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

private struct TerminalPaneTabStrip: NSViewRepresentable {
    let tabs: [Ghostty.SurfaceView]
    let activeID: UUID
    let showsCloseButtons: Bool
    let onFocus: () -> Void
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onClose: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus, onSelect: onSelect, onNew: onNew, onClose: onClose)
    }

    func makeNSView(context: Context) -> PaneNativeTabStripHostView {
        let view = PaneNativeTabStripHostView()
        view.configure(
            tabs: tabs,
            activeID: activeID,
            showsCloseButtons: showsCloseButtons,
            coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PaneNativeTabStripHostView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.onSelect = onSelect
        context.coordinator.onNew = onNew
        context.coordinator.onClose = onClose
        view.configure(
            tabs: tabs,
            activeID: activeID,
            showsCloseButtons: showsCloseButtons,
            coordinator: context.coordinator)
    }

    final class Coordinator: NSObject {
        var onFocus: () -> Void
        var onSelect: (UUID) -> Void
        var onNew: () -> Void
        var onClose: (UUID) -> Void

        init(
            onFocus: @escaping () -> Void,
            onSelect: @escaping (UUID) -> Void,
            onNew: @escaping () -> Void,
            onClose: @escaping (UUID) -> Void
        ) {
            self.onFocus = onFocus
            self.onSelect = onSelect
            self.onNew = onNew
            self.onClose = onClose
        }
    }
}

private final class PaneNativeTabStripHostView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let tabStackView = NSStackView()
    private let addButton = NSButton()
    private var currentTabs: [Ghostty.SurfaceView] = []
    private var currentActiveID: UUID?
    private var currentShowsCloseButtons = false
    private var lastRenderedSignature: String = ""
    private weak var coordinator: TerminalPaneTabStrip.Coordinator?
    private var titleObservers: [UUID: AnyCancellable] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = .headerView
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        addSubview(backgroundView)

        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.orientation = .horizontal
        tabStackView.alignment = .centerY
        tabStackView.spacing = 4
        backgroundView.addSubview(tabStackView)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .texturedRounded
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: AppLocalization.localizedText("New Pane Tab"))
        addButton.contentTintColor = .secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(onNewTab(_:))
        addButton.setButtonType(.momentaryPushIn)
        backgroundView.addSubview(addButton)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tabStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            tabStackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
            tabStackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
            tabStackView.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),

            addButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 18),
            addButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        let separator = CALayer()
        separator.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.addSublayer(separator)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.first?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        updateTabWidths()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    func configure(
        tabs: [Ghostty.SurfaceView],
        activeID: UUID,
        showsCloseButtons: Bool,
        coordinator: TerminalPaneTabStrip.Coordinator
    ) {
        self.coordinator = coordinator
        currentTabs = tabs
        currentActiveID = activeID
        currentShowsCloseButtons = showsCloseButtons
        syncTitleObservers()
        let signature = renderedSignature(
            tabs: tabs,
            activeID: activeID,
            showsCloseButtons: showsCloseButtons)
        if signature != lastRenderedSignature {
            lastRenderedSignature = signature
            rebuildTabs()
        } else {
            updateTabWidths()
        }
    }

    private func rebuildTabs() {
        tabStackView.arrangedSubviews.forEach { view in
            tabStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !currentTabs.isEmpty else { return }

        for (index, surfaceView) in currentTabs.enumerated() {
            let itemView = PaneNativeTabButtonView(
                tabID: surfaceView.id,
                title: paneTitle(for: surfaceView, index: index),
                isActive: surfaceView.id == currentActiveID,
                showsCloseButton: currentShowsCloseButtons,
                onFocus: { [weak coordinator] in coordinator?.onFocus() },
                onSelect: { [weak coordinator] id in coordinator?.onSelect(id) },
                onClose: { [weak coordinator] id in coordinator?.onClose(id) })
            tabStackView.addArrangedSubview(itemView)
        }

        updateTabWidths()
    }

    private func syncTitleObservers() {
        let currentIDs = Set(currentTabs.map(\.id))
        titleObservers = titleObservers.filter { currentIDs.contains($0.key) }

        for surfaceView in currentTabs where titleObservers[surfaceView.id] == nil {
            titleObservers[surfaceView.id] = surfaceView.$title
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.rebuildTabs()
                }
        }
    }

    private func updateTabWidths() {
        let tabViews = tabStackView.arrangedSubviews.compactMap { $0 as? PaneNativeTabButtonView }
        guard !tabViews.isEmpty else { return }

        let reservedWidth: CGFloat = 42
        let spacingWidth: CGFloat = CGFloat(max(tabViews.count - 1, 0)) * tabStackView.spacing
        let availableWidth = max(bounds.width - reservedWidth - 16 - spacingWidth, 48)
        let maximumTabWidth = max(44, floor(availableWidth / CGFloat(tabViews.count)))
        for view in tabViews {
            view.updateMaximumWidth(maximumTabWidth)
        }
    }

    private func renderedSignature(
        tabs: [Ghostty.SurfaceView],
        activeID: UUID,
        showsCloseButtons: Bool
    ) -> String {
        let ids = tabs.map(\.id.uuidString).joined(separator: ",")
        return "\(ids)|\(activeID.uuidString)|\(showsCloseButtons)"
    }

    private func paneTitle(for surfaceView: Ghostty.SurfaceView, index: Int) -> String {
        let trimmed = surfaceView.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(AppLocalization.localizedText("Tab")) \(index + 1)" : trimmed
    }

    @objc private func onNewTab(_ sender: Any?) {
        coordinator?.onFocus()
        coordinator?.onNew()
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.onFocus()
        super.mouseDown(with: event)
    }
}

private final class PaneNativeTabButtonView: NSView {
    private let tabID: UUID
    private let onFocus: () -> Void
    private let onSelect: (UUID) -> Void
    private let onClose: (UUID) -> Void

    init(
        tabID: UUID,
        title: String,
        isActive: Bool,
        showsCloseButton: Bool,
        onFocus: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.tabID = tabID
        self.onFocus = onFocus
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = isActive ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(isActive ? 0.45 : 0).cgColor
        layer?.backgroundColor = (isActive
            ? NSColor.windowBackgroundColor.withAlphaComponent(0.96)
            : NSColor.clear
        ).cgColor

        let selectButton = NSButton(title: title, target: self, action: #selector(handleSelect(_:)))
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.isBordered = false
        selectButton.setButtonType(.momentaryChange)
        selectButton.font = .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
        selectButton.lineBreakMode = .byTruncatingTail
        selectButton.contentTintColor = isActive ? .labelColor : .secondaryLabelColor
        selectButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: AppLocalization.localizedText("Close Pane Tab")) ?? NSImage(), target: self, action: #selector(handleClose(_:)))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.setButtonType(.momentaryChange)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isHidden = !showsCloseButton

        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(selectButton)
        addSubview(closeButton)

        let maximumWidthConstraint = widthAnchor.constraint(lessThanOrEqualToConstant: 160)
        maximumWidthConstraint.identifier = "paneTabMaximumWidth"
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            maximumWidthConstraint,
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            selectButton.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            closeButton.leadingAnchor.constraint(equalTo: selectButton.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 12),
            closeButton.heightAnchor.constraint(equalToConstant: 12),
            selectButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    @objc private func handleSelect(_ sender: Any?) {
        onFocus()
        onSelect(tabID)
    }

    @objc private func handleClose(_ sender: Any?) {
        onFocus()
        onClose(tabID)
    }

    func updateMaximumWidth(_ width: CGFloat) {
        constraints.first(where: { $0.identifier == "paneTabMaximumWidth" })?.constant = width
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}
