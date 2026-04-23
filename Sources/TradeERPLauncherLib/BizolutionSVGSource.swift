import Foundation

/// SVG-Vorlagen: Dateien unter `Resources/` (SPM-Ressource + Kopie ins `.app` via `Scripts/build_app.sh`); eingebetteter Fallback nur für die Bildmarke.
enum BizolutionSVGSource {
    /// Liest `bizolution-mark-farbe-rgb.svg` aus `Bundle.main` oder `Bundle.module`.
    static func markCroppedSVGForRuntime() -> String {
        loadBundledSVG(named: "bizolution-mark-farbe-rgb") ?? markCroppedEmbedded
    }

    /// Liest `bizolution-logo-farbe-rgb.svg` bzw. bei `isDark` `bizolution-logo-farbe-dark.svg` (weiße Textmarke) aus dem Bundle.
    /// Ressourcen der Lib liegen in `…_TradeERPLauncherLib.bundle` — zuerst `Bundle.module`, sonst schlägt `Bundle.main` oft fehl.
    static func fullLogoSVGForRuntime(isDark: Bool) -> String {
        if isDark {
            if let s = loadBundledSVG(named: "bizolution-logo-farbe-dark") {
                return s
            }
            if let light = loadBundledSVG(named: "bizolution-logo-farbe-rgb") {
                return Self.darkTextmarkByPatchingWordmarkFill(light)
            }
            return fullLogoEmbeddedMinimalDark
        }
        return loadBundledSVG(named: "bizolution-logo-farbe-rgb") ?? fullLogoEmbeddedMinimal
    }

    private static func loadBundledSVG(named base: String) -> String? {
        for u in svgURLs(named: base) {
            if let s = try? String(contentsOf: u, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }

    /// Einzige Vorkommen von `#00004f` im Light-Volllogo: Textmarke `.cls-2`.
    private static func darkTextmarkByPatchingWordmarkFill(_ svg: String) -> String {
        svg.replacingOccurrences(of: "fill: #00004f;", with: "fill: #ffffff;")
    }

    private static func svgURLs(named base: String) -> [URL] {
        [Bundle.module.url(forResource: base, withExtension: "svg"),
         Bundle.main.url(forResource: base, withExtension: "svg")].compactMap { $0 }
    }

    private static let markCroppedEmbedded: String = #"""
<?xml version="1.0" encoding="UTF-8"?>
<svg id="Bildmarke" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 72.19 771.61 771.61">
  <defs>
    <style>
      .cls-1 {
        fill: url(#Unbenannter_Verlauf_129-2);
      }

      .cls-2 {
        fill: url(#Unbenannter_Verlauf_129);
      }

      .cls-3 {
        fill: url(#Unbenannter_Verlauf_115);
      }
    </style>
    <linearGradient id="Unbenannter_Verlauf_129" data-name="Unbenannter Verlauf 129" x1="427.22" y1="120.66" x2="567.08" y2="504.91" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2fd4e0"/>
      <stop offset="1" stop-color="#1927dd"/>
    </linearGradient>
    <linearGradient id="Unbenannter_Verlauf_129-2" data-name="Unbenannter Verlauf 129" x1="238.51" y1="173.04" x2="373.02" y2="542.62" xlink:href="#Unbenannter_Verlauf_129"/>
    <linearGradient id="Unbenannter_Verlauf_115" data-name="Unbenannter Verlauf 115" x1="567.6" y1="747.49" x2="330.33" y2="420.91" gradientUnits="userSpaceOnUse">
      <stop offset=".27" stop-color="#ff5800"/>
      <stop offset=".55" stop-color="#ff7b00"/>
      <stop offset=".96" stop-color="#ffb600"/>
    </linearGradient>
  </defs>
  <rect class="cls-2" x="430.97" y="189.04" width="66.47" height="66.47" rx="6" ry="6"/>
  <path class="cls-1" d="M349.63,307.83h-101.42v-112.79c0-3.31-2.69-6-6-6h-54.47c-3.31,0-6,2.69-6,6v280.68c0,68.71,41.49,127.91,100.72,153.87l63.38-52.53c-54.18-1.99-97.63-46.69-97.63-101.34v-101.42h101.42c23.71,0,45.54,8.17,62.84,21.86h84.98c-28.4-52.55-84-88.33-147.81-88.33Z"/>
  <path class="cls-3" d="M584.45,515.19l-184.07,152.59h183.49c3.31,0,6,2.69,6,6v54.47c0,3.31-2.69,6-6,6h-268.92c-3.81,0-6.9-3.09-6.9-6.9v-62.59c0-4.47,1.99-8.7,5.43-11.55l184.07-152.59h-183.49c-3.31,0-6-2.69-6-6v-54.47c0-3.31,2.69-6,6-6h268.92c3.81,0,6.9,3.09,6.9,6.9v62.59c0,4.47-1.99,8.7-5.43,11.55Z"/>
</svg>
"""#

    /// Minimaler Platzhalter, falls weder `.app` noch Test-Bundle die Logo-SVG enthält.
    private static let fullLogoEmbeddedMinimal: String = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 32"><text x="4" y="22" fill="#00004f" font-family="system-ui,sans-serif" font-size="14">Bizolution</text></svg>
"""#

    private static let fullLogoEmbeddedMinimalDark: String = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 32"><text x="4" y="22" fill="#ffffff" font-family="system-ui,sans-serif" font-size="14">Bizolution</text></svg>
"""#
}

/// HTML-Hülle für eingebettete SVGs in `WKWebView` (Volllogo und Mark).
enum BizolutionSVGEmbeddedHTML {
    /// `opaquePageHex`: Hintergrund hinter dem SVG, wenn nicht transparent (z. B. `#ffffff` / dunkles Fenster).
    static func document(svg: String, transparentBackground: Bool, opaquePageHex: String? = nil) -> String {
        let bg: String
        if transparentBackground {
            bg = "transparent"
        } else {
            bg = opaquePageHex ?? "#ffffff"
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; height: 100%; background: \(bg); }
          svg { display: block; width: 100%; height: 100%; }
        </style></head><body>\(svg)</body></html>
        """
    }
}
