import AppKit
import SwiftUI
import WebKit

/// App-Symbol aus dem aktuellen Bundle (Finder-Icon), für die Einstellungs-Kopfzeile.
private enum LauncherAppBundleIcon {
    static func nsImage(pointSize: CGFloat = 48) -> NSImage? {
        let path = Bundle.main.bundlePath
        guard !path.isEmpty else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        let s = NSSize(width: pointSize, height: pointSize)
        guard s.width > 0, s.height > 0 else { return nil }
        icon.size = s
        return icon
    }
}

/// Gleiche Flächenfarbe wie `Color(nsColor: .windowBackgroundColor)` im Aqua- bzw. Dark-Aqua-Kontext (Titelleiste / Header).
private func windowBackgroundHex(forDark isDark: Bool) -> String {
    let name: NSAppearance.Name = isDark ? .darkAqua : .aqua
    guard let appearance = NSAppearance(named: name) else {
        return isDark ? "#1e1e1e" : "#ffffff"
    }
    var hex = isDark ? "#1e1e1e" : "#ffffff"
    appearance.performAsCurrentDrawingAppearance {
        let c = NSColor.windowBackgroundColor
        guard let rgb = c.usingColorSpace(.sRGB) else { return }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        hex = String(format: "#%02x%02x%02x", r, g, b)
    }
    return hex
}

/// Volllogo (Schriftzug) per WebKit; `isDark` kommt von außen — `NSViewRepresentable` hat sonst oft kein zuverlässiges `colorScheme`.
struct BizolutionFullLogoWebView: NSViewRepresentable {
    var isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero)
        w.setValue(false, forKey: "drawsBackground")
        return w
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.appliedDark == isDark { return }
        context.coordinator.appliedDark = isDark
        let svg = BizolutionSVGSource.fullLogoSVGForRuntime(isDark: isDark)
        let pageBg = windowBackgroundHex(forDark: isDark)
        let html = BizolutionSVGEmbeddedHTML.document(svg: svg, transparentBackground: false, opaquePageHex: pageBg)
        webView.loadHTMLString(html, baseURL: Bundle.module.resourceURL)
    }

    final class Coordinator {
        var appliedDark: Bool?
    }
}

struct BizolutionLogoHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Seitenverhältnis `bizolution-logo-farbe-rgb.svg` (`viewBox` 1059.78×286.93).
    private static let fullLogoAspect: CGFloat = 1059.78 / 286.93

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    if let appIcon = LauncherAppBundleIcon.nsImage() {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LauncherProductNaming.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(LauncherProductNaming.settingsHeaderSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(LauncherProductNaming.displayName), \(LauncherProductNaming.settingsHeaderSubtitle)"
                    )
                }
                .layoutPriority(0)

                Spacer(minLength: 8)

                BizolutionFullLogoWebView(isDark: colorScheme == .dark)
                    .aspectRatio(Self.fullLogoAspect, contentMode: .fit)
                    .frame(height: 38)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .layoutPriority(1)
                    .accessibilityLabel("Bizolution Logo")
            }
            Divider()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .padding(.bottom, 2)
    }
}
