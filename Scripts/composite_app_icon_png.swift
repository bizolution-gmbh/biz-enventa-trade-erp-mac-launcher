#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Legt `overlay` pixelgenau auf `base` (links/oben wie bei PNG/rsvg). Ausgabe RGBA, transparent wo kein Bild.
/// Aufruf: composite_app_icon_png.swift <base.png> <overlay.png> <overlayLeft> <overlayTop> <out.png>
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 5,
      let ox = Int(args[2]),
      let oy = Int(args[3])
else {
    fputs(
        "Usage: composite_app_icon_png.swift <base.png> <overlay.png> <overlayLeft> <overlayTop> <out.png>\n",
        stderr
    )
    exit(1)
}

let baseURL = URL(fileURLWithPath: args[0])
let overURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[4])

guard let srcBase = CGImageSourceCreateWithURL(baseURL as CFURL, nil),
      let cgBase = CGImageSourceCreateImageAtIndex(srcBase, 0, nil),
      let srcOver = CGImageSourceCreateWithURL(overURL as CFURL, nil),
      let cgOver = CGImageSourceCreateImageAtIndex(srcOver, 0, nil)
else {
    fputs("Cannot read PNG inputs.\n", stderr)
    exit(1)
}

let w = cgBase.width
let h = cgBase.height
guard w > 0, h > 0 else { exit(1) }
// Overlay darf kleiner sein als Base; Base bestimmt Ausgabemaß.
let ow = cgOver.width
let oh = cgOver.height
guard ow > 0, oh > 0 else { exit(1) }

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
ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
ctx.draw(cgBase, in: CGRect(x: 0, y: 0, width: w, height: h))

// PNG-Top ↔ CG-Unten
let drawY = CGFloat(h - oy - oh)
ctx.draw(cgOver, in: CGRect(x: CGFloat(ox), y: drawY, width: CGFloat(ow), height: CGFloat(oh)))

guard let cgOut = ctx.makeImage() else { exit(1) }

let outTmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("fscl-comp-\(UUID().uuidString).png")
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
try? FileManager.default.removeItem(at: outURL)
try FileManager.default.moveItem(at: outTmp, to: outURL)
