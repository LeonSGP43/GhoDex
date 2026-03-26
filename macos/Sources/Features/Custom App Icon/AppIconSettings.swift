import AppKit

struct AppIconSettings: Equatable {
    static let defaultCustomIconPath = NSString("~/.config/ghodex/GhoDex.icns").expandingTildeInPath
    static let defaultGhostColorHex = "#F5F7FA"
    static let defaultScreenColorHexes = ["#1F4D91", "#56C3FF"]
    static let maxScreenColorCount = 8

    var icon: Ghostty.MacOSIcon
    var customIconPath: String
    var frame: Ghostty.MacOSIconFrame
    var ghostColorHex: String
    var screenColorHexes: [String]

    init(
        icon: Ghostty.MacOSIcon = .official,
        customIconPath: String = AppIconSettings.defaultCustomIconPath,
        frame: Ghostty.MacOSIconFrame = .aluminum,
        ghostColorHex: String = AppIconSettings.defaultGhostColorHex,
        screenColorHexes: [String] = AppIconSettings.defaultScreenColorHexes
    ) {
        self.icon = icon
        self.customIconPath = customIconPath
        self.frame = frame
        self.ghostColorHex = ghostColorHex
        self.screenColorHexes = screenColorHexes
    }

    init(config: Ghostty.Config) {
        let screenColorHexes = config.macosIconScreenColor?.compactMap(\.hexString) ?? []
        self.init(
            icon: config.macosIcon,
            customIconPath: config.macosCustomIcon,
            frame: config.macosIconFrame,
            ghostColorHex: config.macosIconGhostColor?.hexString ?? Self.defaultGhostColorHex,
            screenColorHexes: screenColorHexes.isEmpty ? Self.defaultScreenColorHexes : screenColorHexes
        )
        self = sanitized
    }

    var sanitized: Self {
        let trimmedPath = customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = trimmedPath.isEmpty
            ? Self.defaultCustomIconPath
            : (trimmedPath as NSString).standardizingPath

        let normalizedGhost = NSColor(hex: ghostColorHex)?.hexString ?? Self.defaultGhostColorHex

        var normalizedScreenColors = screenColorHexes
            .compactMap { NSColor(hex: $0)?.hexString }
        if normalizedScreenColors.isEmpty {
            normalizedScreenColors = Self.defaultScreenColorHexes
        }
        if normalizedScreenColors.count > Self.maxScreenColorCount {
            normalizedScreenColors = Array(normalizedScreenColors.prefix(Self.maxScreenColorCount))
        }

        return .init(
            icon: icon,
            customIconPath: normalizedPath,
            frame: frame,
            ghostColorHex: normalizedGhost,
            screenColorHexes: normalizedScreenColors
        )
    }

    var ghostColor: NSColor {
        NSColor(hex: sanitized.ghostColorHex) ?? NSColor(hex: Self.defaultGhostColorHex) ?? .white
    }

    var screenColors: [NSColor] {
        let resolved = sanitized.screenColorHexes.compactMap(NSColor.init(hex:))
        return resolved.isEmpty
            ? Self.defaultScreenColorHexes.compactMap(NSColor.init(hex:))
            : resolved
    }

    var customIconURL: URL {
        URL(fileURLWithPath: sanitized.customIconPath, isDirectory: false)
    }

    var customIconImage: NSImage? {
        NSImage(contentsOf: customIconURL)
    }

    var isCustomIconValid: Bool {
        customIconImage != nil
    }

    var customStyleIcon: ColorizedGhosttyIcon {
        .init(
            screenColors: screenColors,
            ghostColor: ghostColor,
            frame: frame
        )
    }

    func previewImage(in bundle: Bundle = .main) -> NSImage? {
        switch sanitized.icon {
        case .official:
            return bundle.image(forResource: "AppIconImage")
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
        case .custom:
            return customIconImage ?? bundle.image(forResource: "AppIconImage")
        case .customStyle:
            return AppIcon.customStyle(customStyleIcon).image(in: bundle) ?? bundle.image(forResource: "AppIconImage")
        }
    }
}

extension Ghostty.MacOSIcon {
    static let builtInOptions: [Self] = [
        .official,
        .blueprint,
        .chalkboard,
        .glass,
        .holographic,
        .microchip,
        .paper,
        .retro,
        .xray,
    ]
}
