import AppKit
import SwiftUI

enum GhoDexPanelPalette {
    static let accent = Color(red: 0.35, green: 0.43, blue: 0.94)
    static let accentStrong = Color(red: 0.16, green: 0.20, blue: 0.63)
    static let accentSoft = Color(red: 0.81, green: 0.85, blue: 1.0)
    static let accentSurfaceDark = Color(red: 0.12, green: 0.15, blue: 0.33)
    static let accentSurfaceLight = Color(red: 0.87, green: 0.90, blue: 1.0)
    static let accentSurfaceLightRaised = Color(red: 0.78, green: 0.83, blue: 1.0)
}

@MainActor
enum GhosttyChrome {
    static func resolvedBackgroundColor(
        appDelegate: AppDelegate?,
        referenceWindow: NSWindow? = nil
    ) -> NSColor {
        if let terminalWindow = referenceWindow as? TerminalWindow,
           let preferred = terminalWindow.preferredBackgroundColor?.usingColorSpace(.deviceRGB) {
            return preferred
        }

        if let appDelegate {
            return NSColor(appDelegate.ghostty.config.backgroundColor).withAlphaComponent(1)
        }

        return NSColor.windowBackgroundColor
    }

    static func syncWindowAppearance(
        _ window: NSWindow?,
        appDelegate: AppDelegate?,
        referenceWindow: NSWindow? = nil
    ) {
        guard let window else { return }

        if let appDelegate {
            window.appearance = NSAppearance(ghosttyConfig: appDelegate.ghostty.config)
        }

        window.backgroundColor = resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
    }
}

@MainActor
final class GhosttyChromeTheme: ObservableObject {
    @Published private(set) var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    @Published private(set) var backgroundNSColor: NSColor = .windowBackgroundColor
    @Published private(set) var colorScheme: ColorScheme = .light

    var isLight: Bool {
        colorScheme == .light
    }

    func apply(backgroundColor: NSColor) {
        let resolved = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        self.backgroundNSColor = resolved
        self.backgroundColor = Color(nsColor: resolved)
        self.colorScheme = resolved.isLightColor ? .light : .dark
    }
}

struct GhosttyTintedBackground: View {
    @EnvironmentObject private var theme: GhosttyChromeTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Rectangle()
                .fill(theme.backgroundColor)
                .blendMode(.color)
        }
        .compositingGroup()
    }
}

extension View {
    func panelSurface() -> some View {
        modifier(GhosttyPanelSurfaceModifier())
    }

    func subpanelSurface() -> some View {
        modifier(GhosttySubpanelSurfaceModifier())
    }
}

private struct GhosttyPanelSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color(red: 0.14, green: 0.15, blue: 0.18),
                                    Color(red: 0.11, green: 0.12, blue: 0.15),
                                ]
                                : [
                                    Color.white.opacity(0.96),
                                    Color(red: 0.95, green: 0.96, blue: 0.98),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.18 : 0.08),
                        lineWidth: 1
                    )
            )
    }
}

private struct GhosttySubpanelSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.035),
                                ]
                                : [
                                    Color.white.opacity(0.92),
                                    Color(red: 0.96, green: 0.97, blue: 0.99),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.16 : 0.08),
                        lineWidth: 1
                    )
            )
    }
}
