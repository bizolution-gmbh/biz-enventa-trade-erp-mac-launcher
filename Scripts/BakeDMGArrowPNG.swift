#!/usr/bin/env swift
// Optional: schreibt Sources/TradeERPLauncherLib/Resources/dmg_arrow.png (240×120 @1x, transparent).
// Üblich: Pfeil im Grafikprogramm bearbeiten. Dieses Skript nur, wenn dieselbe Kurve wie früher reproduziert
// werden soll — siehe Scripts/DMG_HINTERGRUND.txt
// Aufruf: swift Scripts/BakeDMGArrowPNG.swift [<repo-root>]
//
// Geometrie: **arrowHalf** und **arrowBulge** müssen mit Scripts/RenderDMGBackground.swift übereinstimmen.
// bakeW×bakeH: Pfeil zentriert wie im 400×200-Hintergrund; bei geänderter Asset-Größe Renderer-Rect prüfen.

import AppKit
import CoreGraphics
import Foundation

let arrowHalf: CGFloat = 54
let arrowBulge: CGFloat = 28
let lineWidth: CGFloat = 14
let headLen: CGFloat = 36
let headW: CGFloat = 34

let bakeW: CGFloat = 240
let bakeH: CGFloat = 120
let arrowBlueDark = NSColor(red: 0x1a / 255, green: 0x5f / 255, blue: 0xb4 / 255, alpha: 1)

func cubicPoint(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
    let mt = 1 - t
    let a = mt * mt * mt
    let b = 3 * mt * mt * t
    let c = 3 * mt * t * t
    let d = t * t * t
    return CGPoint(
        x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
        y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
    )
}

func splitCubicLeft(u: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    let p01 = CGPoint(x: (1 - u) * p0.x + u * p1.x, y: (1 - u) * p0.y + u * p1.y)
    let p12 = CGPoint(x: (1 - u) * p1.x + u * p2.x, y: (1 - u) * p1.y + u * p2.y)
    let p23 = CGPoint(x: (1 - u) * p2.x + u * p3.x, y: (1 - u) * p2.y + u * p3.y)
    let p012 = CGPoint(x: (1 - u) * p01.x + u * p12.x, y: (1 - u) * p01.y + u * p12.y)
    let p123 = CGPoint(x: (1 - u) * p12.x + u * p23.x, y: (1 - u) * p12.y + u * p23.y)
    let p0123 = CGPoint(x: (1 - u) * p012.x + u * p123.x, y: (1 - u) * p012.y + u * p123.y)
    return (p0, p01, p012, p0123)
}

func projectRoot() -> String {
    if CommandLine.arguments.count > 1 { return CommandLine.arguments[1] }
    let cwd = FileManager.default.currentDirectoryPath
    if cwd.hasSuffix("/Scripts") { return (cwd as NSString).deletingLastPathComponent }
    return cwd
}

let root = projectRoot()
let outPNG = (root as NSString).appendingPathComponent("Sources/TradeERPLauncherLib/Resources/dmg_arrow.png")

let centerX = bakeW / 2
let rowCocoa = bakeH / 2
let ax1 = centerX - arrowHalf
let ax2 = centerX + arrowHalf
let span = ax2 - ax1
let p0 = CGPoint(x: ax1, y: rowCocoa)
let p1 = CGPoint(x: ax1 + span * 0.28, y: rowCocoa + arrowBulge)
let p2 = CGPoint(x: ax1 + span * 0.72, y: rowCocoa + arrowBulge)
let p3 = CGPoint(x: ax2, y: rowCocoa)

let targetShaftToTip = headLen - lineWidth * 0.35
var tLo: CGFloat = 0
var tHi: CGFloat = 1
for _ in 0 ..< 50 {
    let mid = (tLo + tHi) * 0.5
    let pm = cubicPoint(mid, p0, p1, p2, p3)
    let dTip = hypot(p3.x - pm.x, p3.y - pm.y)
    if dTip > targetShaftToTip {
        tLo = mid
    } else {
        tHi = mid
    }
}
let tCut = max(0.02, min((tLo + tHi) * 0.5, 0.998))

let (q0, q1, q2, q3) = splitCubicLeft(u: tCut, p0: p0, p1: p1, p2: p2, p3: p3)
let spine = CGMutablePath()
spine.move(to: q0)
spine.addCurve(to: q3, control1: q1, control2: q2)

let ribbon = spine.copy(
    strokingWithWidth: lineWidth,
    lineCap: .round,
    lineJoin: .round,
    miterLimit: 4,
    transform: .identity
)

let pCut = cubicPoint(tCut, p0, p1, p2, p3)
let dxs = p3.x - pCut.x
let dys = p3.y - pCut.y
let slen = max(hypot(dxs, dys), 1)
let uSpine = CGPoint(x: dxs / slen, y: dys / slen)
let px = -uSpine.y * headW * 0.5
let py = uSpine.x * headW * 0.5
let left = CGPoint(x: pCut.x + px, y: pCut.y + py)
let right = CGPoint(x: pCut.x - px, y: pCut.y - py)
let tip = p3

let head = NSBezierPath()
head.move(to: left)
head.line(to: tip)
head.line(to: right)
head.close()

let Wi = Int(bakeW)
let Hi = Int(bakeH)
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
rep.size = NSSize(width: bakeW, height: bakeH)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx
NSColor.clear.set()
NSRect(x: 0, y: 0, width: bakeW, height: bakeH).fill()

arrowBlueDark.setFill()
NSBezierPath(cgPath: ribbon).fill()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Fehler: PNG-Kodierung fehlgeschlagen.\n", stderr)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outPNG))
print(outPNG)
