import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let githubURL = URL(string: "https://github.com/LeonSGP43/GhoDex")
    private let docsURL = URL(string: "https://github.com/LeonSGP43/GhoDex#readme")

    private func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var bundleBuild: String? { bundleString("CFBundleVersion") }
    private var commit: String? { bundleString("GhoDexCommit") }
    private var version: String? { bundleString("CFBundleShortVersionString") }
    private var buildConfiguration: String? { bundleString("GhoDexBuildConfiguration") }
    private var buildTimestamp: String? { bundleString("GhoDexBuildTimestamp") }
    private var buildFingerprint: String? { bundleString("GhoDexBuild") }
    private var buildBranch: String? { bundleString("GhoDexBuildBranch") }
    private var copyright: String? { bundleString("NSHumanReadableCopyright") }
    private var permissionAccessDiagnostics: AppPermissionAccessDiagnostics {
        AppPermissionAccessDiagnostics.current(bundleURL: Bundle.main.bundleURL)
    }
    private var workspaceState: String? {
        guard let raw = bundleString("GhoDexBuildWorkspaceState")?.lowercased() else { return nil }
        switch raw {
        case "clean":
            return L10n.About.workspaceClean
        case "dirty":
            return L10n.About.workspaceDirty
        default:
            return raw
        }
    }

    #if os(macOS)
    // This creates a background style similar to the Apple "About My Mac" Window
    private struct VisualEffectBackground: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        let isEmphasized: Bool

        init(material: NSVisualEffectView.Material,
             blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
             isEmphasized: Bool = false) {
            self.material = material
            self.blendingMode = blendingMode
            self.isEmphasized = isEmphasized
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
            nsView.isEmphasized = isEmphasized
        }

        func makeNSView(context: Context) -> NSVisualEffectView {
            let visualEffect = NSVisualEffectView()
            visualEffect.autoresizingMask = [.width, .height]
            return visualEffect
        }
    }
    #endif

    var body: some View {
        VStack(alignment: .center) {
            CyclingIconView()

            VStack(alignment: .center, spacing: 32) {
                VStack(alignment: .center, spacing: 8) {
                    Text("GhoDex")
                        .bold()
                        .font(.title)
                    Text(L10n.About.tagline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption)
                        .tint(.secondary)
                        .opacity(0.8)
                }
                .textSelection(.enabled)

                VStack(spacing: 2) {
                    if let version {
                        PropertyRow(label: L10n.About.version, text: version)
                    }
                    if let bundleBuild, bundleBuild != version {
                        PropertyRow(label: L10n.About.build, text: bundleBuild)
                    }
                    if let buildConfiguration {
                        PropertyRow(label: L10n.About.configuration, text: buildConfiguration)
                    }
                    if let buildTimestamp {
                        PropertyRow(label: L10n.About.builtAt, text: buildTimestamp)
                    }
                    if let workspaceState {
                        PropertyRow(label: L10n.About.workspace, text: workspaceState)
                    }
                    if let buildBranch {
                        PropertyRow(label: L10n.About.branch, text: buildBranch)
                    }
                    if let commit, commit != "",
                       let url = githubURL?
                        .appendingPathComponent("commit")
                        .appendingPathComponent(commit) {
                        PropertyRow(label: L10n.About.commit, text: commit, url: url)
                    }
                    if let buildFingerprint {
                        PropertyRow(label: L10n.About.fingerprint, text: buildFingerprint)
                    }
                    PropertyRow(
                        label: L10n.Settings.permissionsSigningTitle,
                        text: permissionAccessDiagnostics.statusText
                    )
                    if let bundleIdentifier = permissionAccessDiagnostics.bundleIdentifier,
                       bundleIdentifier.isEmpty == false {
                        PropertyRow(
                            label: L10n.Settings.permissionsBundleIdentifier,
                            text: bundleIdentifier
                        )
                    }
                    if let teamIdentifier = permissionAccessDiagnostics.teamIdentifier,
                       teamIdentifier.isEmpty == false {
                        PropertyRow(
                            label: L10n.Settings.permissionsTeamIdentifier,
                            text: teamIdentifier
                        )
                    }
                    if let signerSummary = permissionAccessDiagnostics.signerSummary,
                       signerSummary.isEmpty == false {
                        PropertyRow(
                            label: L10n.Settings.permissionsSignerSummary,
                            text: signerSummary
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if let url = docsURL {
                        Button(L10n.About.docs) {
                            openURL(url)
                        }
                    }
                    if let url = githubURL {
                        Button(L10n.About.github) {
                            openURL(url)
                        }
                    }
                }

                if let copy = self.copyright {
                    Text(copy)
                        .font(.caption)
                        .textSelection(.enabled)
                        .tint(.secondary)
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(32)
        .frame(minWidth: 420)
        #if os(macOS)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        #endif
    }

    private struct PropertyRow: View {
        private let label: String
        private let text: String
        private let url: URL?

        init(label: String, text: String, url: URL? = nil) {
            self.label = label
            self.text = text
            self.url = url
        }

        @ViewBuilder private var textView: some View {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .tint(.secondary)
                .opacity(0.8)
                .monospaced()
                .fixedSize(horizontal: false, vertical: true)
        }

        var body: some View {
            HStack(alignment: .top, spacing: 4) {
                Text(label)
                    .frame(width: 126, alignment: .trailing)
                    .padding(.trailing, 2)
                if let url {
                    Link(destination: url) {
                        textView
                    }
                } else {
                    textView
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
