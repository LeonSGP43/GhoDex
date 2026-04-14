import AppKit

struct AppIconSettings: Equatable {
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
        switch sanitized.icon {
        case .official:
            return AppIcon.officialImage(in: bundle, appBundleURL: bundle.bundleURL)
        case .ghodex:
            return AppIcon.ghodex.image(in: bundle)
        case .banana:
            return AppIcon.banana.image(in: bundle)
        case .blueprint:
            return AppIcon.blueprint.image(in: bundle)
        case .chalkboard:
            return AppIcon.chalkboard.image(in: bundle)
        case .glass:
            return AppIcon.glass.image(in: bundle)
        case .holographic:
            return AppIcon.holographic.image(in: bundle)
        case .microchip:
            return AppIcon.microchip.image(in: bundle)
        case .paper:
            return AppIcon.paper.image(in: bundle)
        case .retro:
            return AppIcon.retro.image(in: bundle)
        case .xray:
            return AppIcon.xray.image(in: bundle)
        case .custom, .customStyle:
            return AppIcon.officialImage(in: bundle, appBundleURL: bundle.bundleURL)
        }
    }
}
