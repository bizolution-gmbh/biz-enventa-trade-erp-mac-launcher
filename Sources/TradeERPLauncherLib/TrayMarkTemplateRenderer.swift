import AppKit

/// Menüleisten-Icon: Bildmarke (Vektor wie Marke-SVG) plus Play-Dreieck (siehe `BizolutionMarkVectorTemplate`).
enum TrayMarkTemplateRenderer {
    static func menuBarImage(side: CGFloat = 18) -> NSImage {
        BizolutionMarkVectorTemplate.menuBarTemplateImage(side: side)
    }
}
