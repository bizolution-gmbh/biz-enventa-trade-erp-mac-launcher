import AppKit

/// Branding für **Java `-Xdock:icon`** und **FS-Client-Kacheln** — getrennt vom **Launcher**-Symbol (`AppIcon.icns`, grüne Balken).
///
/// **Quelle:** ausschließlich gebündeltes **`Icon.png`** (FS-Client-/Java-Dock-Marke). Kein Fallback auf `AppIcon.icns`, damit das Launcher-Icon nicht an diesen Stellen erscheint.
///
/// **Apple-Hinweise (Darstellung):**
/// - Der **Launcher** nutzt `AppIcon.icns`; `Icon.png` ist nur für Kacheln und die Java-VM (`-Xdock:icon`).
/// - Für Java wenden wir eine **Superellipse-Maske** (Radius ~22 % der Kantenlänge) und **Keyline** an, analog macOS-App-Icons.
enum LauncherBrandingImages {
    /// Keyline / „lebender Bereich“: Inhalt etwas kleiner als die volle 1024-Kachel (vgl. Apple-Icon-Vorlagen).
    private static let dockContentInsetFraction: CGFloat = 0.10
    /// Näherung Squircle-Eckenradius (Anteil der Referenzkante) — mit `Scripts/normalize_iconset_png.swift` und Regel `macos-apple-icons` abstimmen.
    private static let macOSIconSquircleCornerFraction: CGFloat = 0.2237

    /// Mindestgröße (logische Punkte), damit defekte Mini-PNGs ignoriert werden.
    private static let minimumFsClientIconDimension: CGFloat = 16

    private static func isUsableFsClientIconImage(_ image: NSImage) -> Bool {
        let s = image.size
        return s.width >= minimumFsClientIconDimension && s.height >= minimumFsClientIconDimension
    }

    /// `Bundle.main` (`…/Contents/Resources/`), sonst SwiftPM-Ressourcen-`.bundle` neben dem Binary.
    private static func urlForBundledFsClientIconPNG() -> URL? {
        if let u = Bundle.main.url(forResource: "Icon", withExtension: "png"),
           FileManager.default.isReadableFile(atPath: u.path) {
            return u
        }
        let execDir = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: execDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for dir in entries where dir.pathExtension == "bundle" {
            guard let b = Bundle(url: dir),
                  let u = b.url(forResource: "Icon", withExtension: "png"),
                  FileManager.default.isReadableFile(atPath: u.path)
            else { continue }
            return u
        }
        return nil
    }

    /// Nur gebündeltes **`Icon.png`** (Basis für Kachel oben links und Java-Dock).
    static func sourceImageForJavaAndTiles() -> NSImage? {
        guard let url = urlForBundledFsClientIconPNG(),
              let img = NSImage(contentsOf: url),
              !img.representations.isEmpty,
              isUsableFsClientIconImage(img)
        else { return nil }
        return img
    }

    /// Kachel-Icon: gleiche Maske wie Java-Dock, Darstellung ~80 pt.
    static func shortcutsTileIcon() -> NSImage? {
        guard let src = sourceImageForJavaAndTiles() else { return nil }
        let masked = dockApplicationIcon(from: src)
        let out = NSImage(size: NSSize(width: 80, height: 80), flipped: false) { r in
            NSColor.clear.set()
            r.fill()
            let s = masked.size
            guard s.width > 0, s.height > 0 else { return true }
            masked.draw(
                in: r,
                from: NSRect(origin: .zero, size: s),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
        out.isTemplate = false
        return out
    }

    /// Tray-Menü neben jedem Shortcut: dieselbe **Java-/FS-Client-**Marke wie `-Xdock:icon` (`Icon.png` + Superellipse).
    static func trayMenuJavaApplicationIcon(pointSize: CGFloat = 16) -> NSImage? {
        guard let src = sourceImageForJavaAndTiles() else { return nil }
        let masked = dockApplicationIcon(from: src)
        let s = max(8, pointSize)
        let out = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            NSColor.clear.set()
            rect.fill()
            let ms = masked.size
            guard ms.width > 0, ms.height > 0 else { return true }
            NSGraphicsContext.current?.imageInterpolation = .high
            masked.draw(
                in: rect,
                from: NSRect(origin: .zero, size: ms),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
        out.isTemplate = false
        return out
    }

    /// Superellipse-Clip (Radius ~22 % der Kantenlänge) + Keyline-Einzug für Darstellung nahe am macOS-App-Icon-Raster.
    static func dockApplicationIcon(from source: NSImage) -> NSImage {
        let dim: CGFloat = 1024
        let inset = dim * dockContentInsetFraction
        let bounds = NSRect(x: 0, y: 0, width: dim, height: dim)
        let inner = bounds.insetBy(dx: inset, dy: inset)
        let corner = dim * macOSIconSquircleCornerFraction
        return NSImage(size: bounds.size, flipped: false) { dst in
            NSColor.clear.set()
            dst.fill()
            let clip = NSBezierPath(roundedRect: dst, xRadius: corner, yRadius: corner)
            clip.addClip()
            let src = source.size
            guard src.width > 0, src.height > 0 else { return true }
            let ar = src.width / src.height
            var dr = inner
            if ar > inner.width / inner.height {
                let h = inner.width / ar
                dr.origin.y += (inner.height - h) / 2
                dr.size.height = h
            } else {
                let w = inner.height * ar
                dr.origin.x += (inner.width - w) / 2
                dr.size.width = w
            }
            source.draw(
                in: dr,
                from: NSRect(origin: .zero, size: src),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
    }

    /// Schreibt maskiertes 1024×1024-PNG für `java -Xdock:icon=…` aus **`Icon.png`**.
    static func writeJavaDockIconPNGFromBundleIfNeeded() -> String? {
        guard let image = sourceImageForJavaAndTiles() else { return nil }
        let docked = dockApplicationIcon(from: image)
        guard let tiff = docked.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        rep.size = NSSize(width: 1024, height: 1024)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dest = AppPaths.javaDockIconPNG
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: dest, options: .atomic)
            return dest.path
        } catch {
            return nil
        }
    }
}
