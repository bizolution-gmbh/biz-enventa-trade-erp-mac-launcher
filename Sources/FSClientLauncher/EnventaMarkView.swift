import AppKit
import SwiftUI
import WebKit

/// Markenzeichen: `enventa-mark-cropped.svg` (Bundle) bzw. eingebetteter Fallback — nur die drei grünen Pfade.
struct EnventaMarkWebView: NSViewRepresentable {
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
        let html = EnventaSVGEmbeddedHTML.document(svg: EnventaSVGSource.markCroppedSVGForRuntime(), transparentBackground: false)
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loaded = false
    }
}
