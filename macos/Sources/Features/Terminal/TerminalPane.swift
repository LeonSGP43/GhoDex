import Cocoa
import GhoDexKit

/// A split leaf that owns a pane-local tab stack.
final class TerminalPane: NSView, ObservableObject, Codable, Identifiable {
    let id: UUID

    private(set) var surfaces: [Ghostty.SurfaceView]
    private(set) var activeSurfaceID: UUID

    var activeSurface: Ghostty.SurfaceView {
        surfaces.first(where: { $0.id == activeSurfaceID }) ?? surfaces[0]
    }

    init(id: UUID = UUID(), surfaces: [Ghostty.SurfaceView], activeSurfaceID: UUID? = nil) {
        precondition(!surfaces.isEmpty, "TerminalPane requires at least one surface")
        self.id = id
        self.surfaces = surfaces
        let initialActiveID = activeSurfaceID ?? surfaces[0].id
        self.activeSurfaceID = surfaces.contains(where: { $0.id == initialActiveID }) ? initialActiveID : surfaces[0].id
        super.init(frame: .zero)
        refreshBounds()
    }

    convenience init(surface: Ghostty.SurfaceView) {
        self.init(surfaces: [surface], activeSurfaceID: surface.id)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for TerminalPane")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case surfaces
        case activeSurfaceID
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(UUID.self, forKey: .id)
        let decodedSurfaces = try container.decode([Ghostty.SurfaceView].self, forKey: .surfaces)
        let decodedActiveID = try container.decode(UUID.self, forKey: .activeSurfaceID)
        self.id = decodedID
        self.surfaces = decodedSurfaces
        self.activeSurfaceID = decodedSurfaces.contains(where: { $0.id == decodedActiveID })
            ? decodedActiveID
            : decodedSurfaces[0].id
        super.init(frame: .zero)
        refreshBounds()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surfaces, forKey: .surfaces)
        try container.encode(activeSurfaceID, forKey: .activeSurfaceID)
    }

    func contains(_ surface: Ghostty.SurfaceView) -> Bool {
        surfaces.contains(where: { $0 === surface })
    }

    func selectSurface(id: UUID) -> Ghostty.SurfaceView? {
        guard surfaces.contains(where: { $0.id == id }) else { return nil }
        activeSurfaceID = id
        refreshBounds()
        return activeSurface
    }

    func appendSurface(_ surface: Ghostty.SurfaceView, activate: Bool = true) {
        let paneSize = frame.size
        if paneSize.width > 0 && paneSize.height > 0 {
            surface.initialSize = paneSize
            surface.setFrameSize(paneSize)
        }
        surfaces.append(surface)
        if activate {
            activeSurfaceID = surface.id
        }
        refreshBounds()
    }

    @discardableResult
    func removeSurface(id: UUID) -> Ghostty.SurfaceView? {
        guard surfaces.count > 1,
              let index = surfaces.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        surfaces.remove(at: index)
        if activeSurfaceID == id {
            let nextIndex = min(index, surfaces.count - 1)
            activeSurfaceID = surfaces[nextIndex].id
        }
        refreshBounds()
        return activeSurface
    }

    func refreshBounds() {
        let surface = activeSurface
        let size = if frame.size.width > 0 && frame.size.height > 0 {
            // Pane-local tab switches must preserve the pane geometry. Falling
            // back to a new surface's default size causes the active pane to
            // momentarily expand and visually cover sibling splits.
            frame.size
        } else if surface.bounds.size.width > 0 && surface.bounds.size.height > 0 {
            surface.bounds.size
        } else if let initialSize = surface.initialSize {
            initialSize
        } else {
            CGSize(width: 800, height: 600)
        }

        setFrameSize(size)
    }
}

extension SplitTree where ViewType == TerminalPane {
    var allSurfaces: [Ghostty.SurfaceView] {
        flatMap(\.surfaces)
    }

    func firstSurface(where predicate: (Ghostty.SurfaceView) -> Bool) -> Ghostty.SurfaceView? {
        allSurfaces.first(where: predicate)
    }

    func contains(_ surface: Ghostty.SurfaceView) -> Bool {
        pane(containing: surface) != nil
    }

    func pane(containing surface: Ghostty.SurfaceView) -> TerminalPane? {
        first(where: { $0.contains(surface) })
    }

    func node(containing surface: Ghostty.SurfaceView) -> Node? {
        guard let pane = pane(containing: surface) else { return nil }
        return root?.node(view: pane)
    }

    func leftmostActiveSurface() -> Ghostty.SurfaceView? {
        root?.leftmostLeaf().activeSurface
    }
}
