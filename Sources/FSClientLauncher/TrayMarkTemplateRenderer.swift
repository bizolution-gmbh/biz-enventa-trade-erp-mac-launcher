import AppKit

/// Menüleisten-Mark: vektorgetreu aus `enventa-mark-cropped.svg` (siehe `EnventaMarkVectorTemplate`).
enum TrayMarkTemplateRenderer {
    static func menuBarImage(side: CGFloat = 18) -> NSImage {
        EnventaMarkVectorTemplate.menuBarTemplateImage(side: side)
    }
}
