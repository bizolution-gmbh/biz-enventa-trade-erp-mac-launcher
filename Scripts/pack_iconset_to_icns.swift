#!/usr/bin/env swift
import Foundation

/// Baut eine `.icns` aus einem `.iconset`-Ordner, indem PNG-Daten als typische `icp4`/`ic11`/…-Chunks
/// geschrieben werden (Länge je Eintrag = 8 + PNG-Bytes, wie bei Apple-`.icns` üblich).
/// Dient als Fallback, falls `iconutil -c icns` (z. B. unter macOS 26) mit „Invalid Iconset“ aussteigt.
let args = CommandLine.arguments.dropFirst()
guard args.count == 2 else {
    fputs("Usage: pack_iconset_to_icns.swift <AppIcon.iconset> <out.icns>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: String(args[args.startIndex]))
let outURL = URL(fileURLWithPath: String(args[args.index(after: args.startIndex)]))

/// Dateiname im Iconset → FourCC (PNG-Nutzlast)
let entries: [(file: String, type: String)] = [
    ("icon_16x16.png", "icp4"),
    ("icon_16x16@2x.png", "ic11"),
    ("icon_32x32.png", "icp5"),
    ("icon_32x32@2x.png", "ic12"),
    ("icon_128x128.png", "ic07"),
    ("icon_128x128@2x.png", "ic13"),
    ("icon_256x256.png", "ic08"),
    ("icon_256x256@2x.png", "ic14"),
    ("icon_512x512.png", "ic09"),
    ("icon_512x512@2x.png", "ic10"),
]

var payload = Data()
for e in entries {
    let url = iconsetURL.appendingPathComponent(e.file)
    guard let png = try? Data(contentsOf: url), png.count >= 8, png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) else {
        fputs("Missing or invalid PNG in iconset: \(url.path)\n", stderr)
        exit(1)
    }
    guard let t = e.type.data(using: .utf8), t.count == 4 else {
        fputs("Internal error: bad FourCC \(e.type)\n", stderr)
        exit(1)
    }
    let entryTotal = 8 + png.count
    guard entryTotal >= 8 else { exit(1) }
    payload.append(t)
    var lenBE = UInt32(entryTotal).bigEndian
    withUnsafeBytes(of: &lenBE) { payload.append(contentsOf: $0) }
    payload.append(png)
}

var out = Data()
out.append(contentsOf: "icns".utf8)
let fileLen = UInt32(8 + payload.count)
var fileLenBE = fileLen.bigEndian
withUnsafeBytes(of: &fileLenBE) { out.append(contentsOf: $0) }
out.append(payload)

do {
    try out.write(to: outURL, options: .atomic)
} catch {
    fputs("Cannot write \(outURL.path): \(error)\n", stderr)
    exit(1)
}
