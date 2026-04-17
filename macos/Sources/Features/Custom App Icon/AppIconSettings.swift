import AppKit

struct AppIconSettings: Equatable {
    private static let previewCacheLock = NSLock()
    private static var previewCache: [Ghostty.MacOSIcon: NSImage] = [:]

    var icon: Ghostty.MacOSIcon

    init(icon: Ghostty.MacOSIcon = .official) {
        self.icon = icon
    }

    init(config: Ghostty.Config) {
        self.init(icon: config.macosIcon.builtInValue)
    }

    var sanitized: Self {
        .init(icon: icon.builtInValue)
    }

    func previewImage(in bundle: Bundle = .main) -> NSImage? {
        let resolvedIcon = sanitized.icon.builtInValue

        Self.previewCacheLock.lock()
        if let cached = Self.previewCache[resolvedIcon] {
            Self.previewCacheLock.unlock()
            return cached
        }
        Self.previewCacheLock.unlock()

        let image: NSImage?
        switch resolvedIcon {
        case .official:
            image = AppIcon.officialImage(in: bundle, appBundleURL: bundle.bundleURL)
        case .ghodex:
            image = AppIcon.ghodex.image(in: bundle)
        case .banana:
            image = AppIcon.banana.image(in: bundle)
        case .blueprint:
            image = AppIcon.blueprint.image(in: bundle)
        case .chalkboard:
            image = AppIcon.chalkboard.image(in: bundle)
        case .glass:
            image = AppIcon.glass.image(in: bundle)
        case .holographic:
            image = AppIcon.holographic.image(in: bundle)
        case .microchip:
            image = AppIcon.microchip.image(in: bundle)
        case .paper:
            image = AppIcon.paper.image(in: bundle)
        case .retro:
            image = AppIcon.retro.image(in: bundle)
        case .xray:
            image = AppIcon.xray.image(in: bundle)
        case .custom, .customStyle:
            image = AppIcon.officialImage(in: bundle, appBundleURL: bundle.bundleURL)
        }

        guard let image else { return nil }

        Self.previewCacheLock.lock()
        if let cached = Self.previewCache[resolvedIcon] {
            Self.previewCacheLock.unlock()
            return cached
        }
        Self.previewCache[resolvedIcon] = image
        Self.previewCacheLock.unlock()
        return image
    }
}
