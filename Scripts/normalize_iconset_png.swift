#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// iconutil erwartet PNG mit Alpha + sRGB. rsvg liefert oft RGBA mit transparentem Rand.
/// Weiß nur als Unterlage; das Quellbild per CGImage zeichnen (NSImage.draw ist hier unzuverlässig).
let args = CommandLine.arguments.dropFirst()
guard let path = args.first else {
    fputs("Usage: normalize_iconset_png.swift <icon.png>\n", stderr)
    exit(1)
}

let fileURL = URL(fileURLWithPath: path)
guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
      let cgIn = CGImageSourceCreateImageAtIndex(src, 0, nil)
else {
    fputs("Cannot read PNG: \(path)\n", stderr)
    exit(1)
}

let w = cgIn.width
let h = cgIn.height
guard w > 0, h > 0 else { exit(1) }

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { exit(1) }
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
guard let ctx = CGContext(
    data: nil,
    width: w,
    height: h,
    bitsPerComponent: 8,
    bytesPerRow: w * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else { exit(1) }

ctx.interpolationQuality = .high

// Außenbereich transparent, damit Finder/Dock/DMG-Volumen **abgerundet** darstellen (wie macOS-App-Icons).
ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

// Abgerundetes Rechteck ≈ Apple-App-Icon-Radius — gleiche Fraktion wie `LauncherBrandingImages.macOSIconSquircleCornerFraction` (Dock/Kacheln).
let side = CGFloat(min(w, h))
let macOSIconSquircleCornerFraction: CGFloat = 0.2237
let corner = max(1, side * macOSIconSquircleCornerFraction)
let clipRect = CGRect(x: 0, y: 0, width: w, height: h)
let rounded = CGPath(
    roundedRect: clipRect,
    cornerWidth: corner,
    cornerHeight: corner,
    transform: nil
)
ctx.addPath(rounded)
ctx.clip()

// Weißer Hintergrund nur innerhalb der Maske (Mark sitzt wie bisher zentriert im rsvg-Canvas).
ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.fill(clipRect)

// Keine vertikale Spiegelung: Offscreen-Bitmap und PNG-Ausgabe sind hier top-aligned.
ctx.draw(cgIn, in: CGRect(x: 0, y: 0, width: w, height: h))

guard let cgOut = ctx.makeImage() else { exit(1) }

let outTmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("fscl-icon-\(UUID().uuidString).png")
guard let dest = CGImageDestinationCreateWithURL(outTmp as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
let props: [CFString: Any] = [
    kCGImagePropertyHasAlpha: true,
    kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
    kCGImageDestinationLossyCompressionQuality: 1.0,
]
CGImageDestinationAddImage(dest, cgOut, props as CFDictionary)
guard CGImageDestinationFinalize(dest) else {
    fputs("Cannot write PNG: \(outTmp.path)\n", stderr)
    exit(1)
}
try? FileManager.default.removeItem(at: fileURL)
try FileManager.default.moveItem(at: outTmp, to: fileURL)
