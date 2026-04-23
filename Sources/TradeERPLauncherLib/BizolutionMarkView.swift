import AppKit
import SwiftUI
import WebKit

/// Markenzeichen: `bizolution-mark-farbe-rgb.svg` (Bundle) bzw. eingebetteter Fallback.
struct BizolutionMarkWebView: NSViewRepresentable {
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
        let html = BizolutionSVGEmbeddedHTML.document(svg: BizolutionSVGSource.markCroppedSVGForRuntime(), transparentBackground: false)
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loaded = false
    }
}
