import AppKit
import SwiftUI
import WebKit

/// Volllogo (Schriftzug) per WebKit.
struct EnventaFullLogoWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero)
        w.setValue(false, forKey: "drawsBackground")
        return w
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loaded { return }
        context.coordinator.loaded = true
        let html = EnventaSVGEmbeddedHTML.document(svg: EnventaSVGSource.fullLogo, transparentBackground: false)
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loaded = false
    }
}

struct EnventaLogoHeader: View {
    /// Seitenverhältnis des eingebetteten Volllogos (`viewBox` 170×36).
    private static let fullLogoAspect: CGFloat = 170 / 36

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                EnventaFullLogoWebView()
                    .aspectRatio(Self.fullLogoAspect, contentMode: .fit)
                    .frame(height: 44)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("enventa Logo")
                Spacer(minLength: 0)
            }
            Divider()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white)
        .padding(.bottom, 4)
    }
}
