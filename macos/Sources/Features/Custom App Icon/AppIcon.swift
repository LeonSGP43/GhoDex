import AppKit
import System

/// The icon style for the Ghostty App.
enum AppIcon: Equatable, Codable {
    case official
    case ghodex
    case banana
    case blueprint
    case chalkboard
    case glass
    case holographic
    case microchip
    case paper
    case retro
    case xray
    /// Save full image data to avoid sandboxing issues
    case custom(_ iconFile: Data)
    case customStyle(_ icon: ColorizedGhosttyIcon)

#if !DOCK_TILE_PLUGIN
    init?(config: Ghostty.Config) {
        switch config.macosIcon {
        case .official:
            return nil
        case .ghodex:
            self = .ghodex
        case .banana:
            self = .banana
        case .blueprint:
            self = .blueprint
        case .chalkboard:
            self = .chalkboard
        case .glass:
            self = .glass
        case .holographic:
            self = .holographic
        case .microchip:
            self = .microchip
        case .paper:
            self = .paper
        case .retro:
            self = .retro
        case .xray:
            self = .xray
        case .custom, .customStyle:
            return nil
        }
    }
#endif

    func image(in bundle: Bundle) -> NSImage? {
        switch self {
        case .official:
            return nil
        case .ghodex:
            return bundle.image(forResource: "GhodexImage")!
        case .banana:
            return bundle.image(forResource: "BananaImage")!
        case .blueprint:
            return bundle.image(forResource: "BlueprintImage")!
        case .chalkboard:
            return bundle.image(forResource: "ChalkboardImage")!
        case .glass:
            return bundle.image(forResource: "GlassImage")!
        case .holographic:
            return bundle.image(forResource: "HolographicImage")!
        case .microchip:
            return bundle.image(forResource: "MicrochipImage")!
        case .paper:
            return bundle.image(forResource: "PaperImage")!
        case .retro:
            return bundle.image(forResource: "RetroImage")!
        case .xray:
            return bundle.image(forResource: "XrayImage")!
        case let .custom(file):
            return NSImage(data: file)
        case let .customStyle(customIcon):
            return customIcon.makeImage(in: bundle)
        }
    }

    static func officialImage(in bundle: Bundle, appBundleURL: URL? = nil) -> NSImage? {
        if let appBundleURL {
            let icon = NSWorkspace.shared.icon(forFile: appBundleURL.path)
            if let iconRep = icon.bestRepresentation(
                for: CGRect(origin: .zero, size: NSSize(width: 1024, height: 1024)),
                context: nil,
                hints: nil
            ) {
                let image = NSImage(size: iconRep.size)
                image.addRepresentation(iconRep)
                return image
            }

            return icon
        }

        guard let iconFile = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else {
            return bundle.image(forResource: "AppIconImage")
        }

        let iconName = URL(fileURLWithPath: iconFile).deletingPathExtension().lastPathComponent
        if let image = bundle.image(forResource: iconName) {
            return image
        }

        if let iconURL = bundle.url(forResource: iconName, withExtension: "icns") {
            return NSImage(contentsOf: iconURL)
        }

        return bundle.image(forResource: "AppIconImage")
    }
}

enum AppBundleIconMutationPolicy {
    /// Avoid mutating transient build products. Writing custom icons to
    /// xcodebuild outputs creates `Icon\r` + Finder metadata and can break
    /// subsequent code-sign passes.
    static func shouldWriteBundleIcon(at appBundleURL: URL?) -> Bool {
        guard let appBundleURL else { return false }
        let path = appBundleURL.path
        if path.contains("/DerivedData/") {
            return false
        }
        if path.contains("/Build/Products/") {
            return false
        }
        if path.contains("/macos/build/") {
            return false
        }
        return true
    }
}
