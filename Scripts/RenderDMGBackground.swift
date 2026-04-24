#!/usr/bin/env swift
// Erzeugt Scripts/dmg_install_background.png — **400×200 @72dpi** (feste Vorgabe).
//
// Ablage: Pfeil und Footer-Logo liegen unter Sources/TradeERPLauncherLib/Resources/ (mit den übrigen Marken-Assets);
// das fertige Hintergrund-PNG liegt unter Scripts/ (Build-Ausgabe, nicht im App-Bundle). Layout-Zahlen für
// create-dmg: Scripts/dmg_layout_constants.sh — bei Geometrie-Änderungen Renderer und Shell synchron halten.
// Details: Scripts/DMG_HINTERGRUND.txt
//
// Zeichnung: Verlauf → Pfeil-PNG (zentriert, Opacity siehe dmgArrowOpacity) → Logo (rsvg). Cocoa: y nach oben.

import AppKit
import Foundation

let W: CGFloat = 400
let H: CGFloat = 200
let iconSize: CGFloat = 88
/// Pfeil-PNG: `NSImage.draw(…, fraction:)` — 0…1, visuell 50 % Deckkraft.
let dmgArrowOpacity: CGFloat = 0.5

/// Footer-Logo: Breite und Höhe in **PNG-Punkten** (klar lesbar; bei anderem Motiv beide Werte anpassen).
/// Footer-Logo: `bizolution-logo-farbe-rgb.svg` (viewBox ~3,69∶1).
let marginBottomCocoa: CGFloat = 10
let logoW: CGFloat = 126
let logoH: CGFloat = 34

/// Oberkante Logo in top-down: H − Rand − Logo-Höhe
let logoTopTD: CGFloat = H - marginBottomCocoa - logoH
/// 10 px oberhalb der Logo-Oberkante (untere Grenze des vertikalen Bandes für die Pfeilmitte)
let bandBottomTD: CGFloat = logoTopTD - 10
/// Pfeilmitte vertikal: Mitte zwischen 0 und bandBottomTD
let arrowCenterTD: CGFloat = (0 + bandBottomTD) / 2
/// Pfeilmitte horizontal: Bildmitte
let arrowCenterX: CGFloat = W / 2

/// Icon-Mitten: horizontal symmetrisch um Pfeil; Pfeilbreite entspricht `dmg_arrow.png`-Layout (arrowHalf).
let arrowHalf: CGFloat = 54
let iconGap: CGFloat = 20
let iconCenterXLeft: CGFloat = arrowCenterX - arrowHalf - iconGap - iconSize / 2
let iconCenterXRight: CGFloat = arrowCenterX + arrowHalf + iconGap + iconSize / 2

/// Finder/create-dmg: Abstand der Icon-Mitte von der UNTERKANTE der Icon-View (bei 1:1-Höhe H).
let iconYFinder: CGFloat = H - arrowCenterTD

// create-dmg-Positionen müssen mit Scripts/dmg_layout_constants.sh übereinstimmen:
//   DMG_ICON_X  = Int(round(iconCenterXLeft))   // arrowHalf=54 → 82
//   DMG_DROP_X  = Int(round(iconCenterXRight)) // → 318
//   DMG_ICON_Y  = in dmg_layout_constants.sh (Finder-Kalibrierung, oft ≠ iconYFinder)

func projectRoot() -> String {
    if CommandLine.arguments.count > 1 { return CommandLine.arguments[1] }
    let env = ProcessInfo.processInfo.environment["FSCL_ROOT"] ?? ""
    if !env.isEmpty { return env }
    let cwd = FileManager.default.currentDirectoryPath
    if cwd.hasSuffix("/Scripts") {
        return (cwd as NSString).deletingLastPathComponent
    }
    return cwd
}

func renderLogoPNG(svgPath: String, widthPx: Int) -> NSImage? {
    let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fscl-dmg-logo-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: out) }

    for bin in ["/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert"] {
        guard FileManager.default.fileExists(atPath: bin) else { continue }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-w", "\(widthPx)", svgPath, "-o", out.path]
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0, let img = NSImage(contentsOf: out) { return img }
    }

    if let img = NSImage(contentsOfFile: svgPath), !img.representations.isEmpty {
        return img
    }
    return nil
}

func drawImage(_ image: NSImage, in rect: NSRect, fraction: CGFloat = 1) {
    let sz = image.size
    guard sz.width > 0, sz.height > 0 else { return }
    image.draw(
        in: rect,
        from: NSRect(origin: .zero, size: sz),
        operation: .sourceOver,
        fraction: fraction
    )
}

let root = projectRoot()
let resDir = (root as NSString).appendingPathComponent("Sources/TradeERPLauncherLib/Resources")
let svgLogo = (resDir as NSString).appendingPathComponent("bizolution-logo-farbe-rgb.svg")
let arrowPNG = (resDir as NSString).appendingPathComponent("dmg_arrow.png")
let outPath = (root as NSString).appendingPathComponent("Scripts/dmg_install_background.png")

let Wi = Int(W)
let Hi = Int(H)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Wi,
    pixelsHigh: Hi,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx

let bgTop = NSColor(calibratedWhite: 0.99, alpha: 1)
let bgBot = NSColor(calibratedWhite: 0.93, alpha: 1)
let grad = NSGradient(colors: [bgBot, bgTop], atLocations: [0, 1], colorSpace: NSColorSpace.deviceRGB)!
grad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

let rowCenterCocoa = H - arrowCenterTD
if let arrow = NSImage(contentsOfFile: arrowPNG) {
    let aw = arrow.size.width
    let ah = arrow.size.height
    let arrowRect = NSRect(
        x: arrowCenterX - aw / 2,
        y: rowCenterCocoa - ah / 2,
        width: aw,
        height: ah
    )
    drawImage(arrow, in: arrowRect, fraction: dmgArrowOpacity)
} else {
    fputs("Hinweis: Pfeil-PNG fehlt (\(arrowPNG)) — Hintergrund ohne Pfeil. Datei anlegen oder `swift Scripts/BakeDMGArrowPNG.swift` ausführen.\n", stderr)
}

let logoRect = NSRect(
    x: (W - logoW) / 2,
    y: marginBottomCocoa,
    width: logoW,
    height: logoH
)
if let logo = renderLogoPNG(svgPath: svgLogo, widthPx: Int(logoW * 2)) {
    drawImage(logo, in: logoRect)
} else {
    fputs("Hinweis: Logo-SVG nicht gerastert (brew install librsvg). Ohne Footer-Logo.\n", stderr)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Fehler: PNG-Kodierung fehlgeschlagen.\n", stderr)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath))
print(outPath)
