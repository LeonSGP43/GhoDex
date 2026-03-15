import AppKit
import SwiftUI

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
    @Published private(set) var colorScheme: ColorScheme = .light

    var isLight: Bool {
        colorScheme == .light
    }

    func apply(backgroundColor: NSColor) {
        let resolved = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
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
        self
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            )
    }

    func subpanelSurface() -> some View {
        self
            .background(
                Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
            )
    }
}
