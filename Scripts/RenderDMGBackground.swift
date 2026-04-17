#!/usr/bin/env swift
// Erzeugt Scripts/dmg_install_background.png — **400×200 @72dpi** (feste Vorgabe).
// Außenfenster: dmg_layout_constants.sh (gleiche Zahl wie PNG-Breite/-höhe oder minimal +Chrome).
//
// Vorgaben (top-down, y nach unten, Ursprung oben links):
// - Logo unten, 10 px zum unteren Rand, horizontal mittig.
// - Pfeil: horizontal Bildmitte W/2; vertikal Mitte zwischen y=0 und (Logo-Oberkante − 10 px).
//   Die Pfeilmitte (Schaft) liegt genau auf diesem Punkt; Finder-Icons: vertikal Icon-Mitte = Pfeilmitte.
// Zeichnung intern Cocoa (y nach oben): rowCocoa = H − y_td.

import AppKit
import Foundation

let W: CGFloat = 400
let H: CGFloat = 200
let iconSize: CGFloat = 88
let brandGreen = NSColor(red: 0x9E / 255, green: 0xBE / 255, blue: 0x2E / 255, alpha: 1)

/// Footer-Logo: Breite und Höhe in **PNG-Punkten** (klar lesbar; bei anderem Motiv beide Werte anpassen).
/// Vorheriges Layout entsprach grob dem SVG enventa-logo-full in ~120×25 px hier — ohne Formel im Code.
let marginBottomCocoa: CGFloat = 10
let logoW: CGFloat = 120
let logoH: CGFloat = 25

/// Oberkante Logo in top-down: H − Rand − Logo-Höhe
let logoTopTD: CGFloat = H - marginBottomCocoa - logoH
/// 10 px oberhalb der Logo-Oberkante (untere Grenze des vertikalen Bandes für die Pfeilmitte)
let bandBottomTD: CGFloat = logoTopTD - 10
/// Pfeilmitte vertikal: Mitte zwischen 0 und bandBottomTD
let arrowCenterTD: CGFloat = (0 + bandBottomTD) / 2
/// Pfeilmitte horizontal: Bildmitte
let arrowCenterX: CGFloat = W / 2

/// Icon-Mitten: horizontal symmetrisch um Pfeil, Abstand so dass 88-px-Icons nicht kollidieren (Pfeilhalblänge 40).
let arrowHalf: CGFloat = 40
let iconGap: CGFloat = 20
let iconCenterXLeft: CGFloat = arrowCenterX - arrowHalf - iconGap - iconSize / 2
let iconCenterXRight: CGFloat = arrowCenterX + arrowHalf + iconGap + iconSize / 2

/// Finder/create-dmg: Abstand der Icon-Mitte von der UNTERKANTE der Icon-View (bei 1:1-Höhe H).
let iconYFinder: CGFloat = H - arrowCenterTD

// create-dmg-Positionen müssen mit Scripts/dmg_layout_constants.sh übereinstimmen:
//   DMG_ICON_X  = Int(round(iconCenterXLeft))
//   DMG_DROP_X  = Int(round(iconCenterXRight))
//   DMG_ICON_Y  = Int(round(iconYFinder))

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

func drawArrowHorizontal(from: NSPoint, to: NSPoint, lineWidth: CGFloat, color: NSColor) {
    color.setStroke()
    color.setFill()

    let dx = to.x - from.x
    let dy = to.y - from.y
    let len = max(hypot(dx, dy), 1)
    let ux = dx / len
    let uy = dy / len
    let headLen: CGFloat = 26
    let headW: CGFloat = 20
    let tip = to
    let base = NSPoint(x: to.x - ux * headLen, y: to.y - uy * headLen)
    let perpX = -uy * headW * 0.5
    let perpY = ux * headW * 0.5
    let left = NSPoint(x: base.x + perpX, y: base.y + perpY)
    let right = NSPoint(x: base.x - perpX, y: base.y - perpY)
    let shaftEnd = NSPoint(x: base.x - ux * 3, y: base.y - uy * 3)

    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: from)
    path.line(to: shaftEnd)
    path.stroke()

    let headPath = NSBezierPath()
    headPath.move(to: left)
    headPath.line(to: tip)
    headPath.line(to: right)
    headPath.close()
    headPath.fill()
}

func drawImage(_ image: NSImage, in rect: NSRect) {
    let sz = image.size
    guard sz.width > 0, sz.height > 0 else { return }
    image.draw(
        in: rect,
        from: NSRect(origin: .zero, size: sz),
        operation: .sourceOver,
        fraction: 1
    )
}

let root = projectRoot()
let svgLogo = (root as NSString).appendingPathComponent("Sources/FSClientLauncherLib/Resources/enventa-logo-full.svg")
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
let ax1 = arrowCenterX - arrowHalf
let ax2 = arrowCenterX + arrowHalf
drawArrowHorizontal(
    from: NSPoint(x: ax1, y: rowCenterCocoa),
    to: NSPoint(x: ax2, y: rowCenterCocoa),
    lineWidth: 11,
    color: brandGreen
)

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
