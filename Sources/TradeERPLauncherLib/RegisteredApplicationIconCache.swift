import AppKit
import CryptoKit
import Foundation

/// Lädt `Icon.png` unter dem Broker-Stamm, speichert dedupliziert als `<SHA256>.png` unter Application Support.
enum RegisteredApplicationIconCache {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let maxDownloadBytes = 4 * 1024 * 1024

    static var directoryURL: URL {
        AppPaths.appDataDirectory.appendingPathComponent("RegisteredAppIcons", isDirectory: true)
    }

    static func fileURL(contentHashHex: String) -> URL {
        directoryURL.appendingPathComponent("\(contentHashHex).png", isDirectory: false)
    }

    /// Lädt `…/Icon.png` unter dem Broker-Stamm; liefert SHA256-Hex, wenn gespeichert oder bereits vorhanden.
    static func downloadAndStorePngIfMissing(brokerRoot: URL) async -> String? {
        let iconURL = brokerRoot.appendingPathComponent("Icon.png", isDirectory: false)
        guard BrokerFetcher.isPermittedOutboundDownloadURL(iconURL) else { return nil }
        var req = URLRequest(url: iconURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        req.setValue("image/png,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let session = BrokerFetcher.sharedOutboundURLSession()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            LaunchLoadTrace.log(
                "RegisteredApplicationIconCache: Download fehlgeschlagen \(LaunchLoadTrace.preview(iconURL.absoluteString)) — \(error.localizedDescription)"
            )
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            LaunchLoadTrace.log(
                "RegisteredApplicationIconCache: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) für \(LaunchLoadTrace.preview(iconURL.absoluteString))"
            )
            return nil
        }
        guard data.count <= maxDownloadBytes, data.count >= pngSignature.count else { return nil }
        guard data.prefix(pngSignature.count) == pngSignature else { return nil }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let dest = fileURL(contentHashHex: hex)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) {
                return hex
            }
            try data.write(to: dest, options: .atomic)
            return hex
        } catch {
            fputs("TradeERPLauncher: RegisteredAppIcons schreiben: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    static func nsImage(contentHashHex: String, pixelSide: CGFloat) -> NSImage? {
        let url = fileURL(contentHashHex: contentHashHex)
        guard FileManager.default.isReadableFile(atPath: url.path),
              let src = NSImage(contentsOf: url),
              !src.representations.isEmpty
        else { return nil }
        let s = max(8, pixelSide)
        let out = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            NSColor.clear.set()
            rect.fill()
            let sz = src.size
            guard sz.width > 0, sz.height > 0 else { return true }
            NSGraphicsContext.current?.imageInterpolation = .high
            src.draw(
                in: rect,
                from: NSRect(origin: .zero, size: sz),
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
}
