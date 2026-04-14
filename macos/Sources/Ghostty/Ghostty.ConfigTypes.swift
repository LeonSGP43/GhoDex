// This file contains the configuration types for Ghostty so that alternate targets
// can get typed information without depending on all the dependencies of GhoDexKit.

extension Ghostty {
    /// A configuration path value that may be optional or required.
    struct ConfigPath: Sendable {
        let path: String
        let optional: Bool
    }

    /// macos-icon
    enum MacOSIcon: String, Sendable {
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
        case custom
        case customStyle = "custom-style"

        static let builtInOptions: [Self] = [
            .official,
            .ghodex,
            .banana,
            .blueprint,
            .chalkboard,
            .glass,
            .holographic,
            .microchip,
            .paper,
            .retro,
            .xray,
        ]

        /// Bundled asset name for built-in icons
        var assetName: String? {
            switch self {
            case .official: return nil
            case .ghodex: return "GhodexImage"
            case .banana: return "BananaImage"
            case .blueprint: return "BlueprintImage"
            case .chalkboard: return "ChalkboardImage"
            case .microchip: return "MicrochipImage"
            case .glass: return "GlassImage"
            case .holographic: return "HolographicImage"
            case .paper: return "PaperImage"
            case .retro: return "RetroImage"
            case .xray: return "XrayImage"
            case .custom, .customStyle: return nil
            }
        }

        var builtInValue: Self {
            Self.builtInOptions.contains(self) ? self : .official
        }
    }

    /// macos-icon-frame
    enum MacOSIconFrame: String, Codable {
        case aluminum
        case beige
        case plastic
        case chrome
    }
}
