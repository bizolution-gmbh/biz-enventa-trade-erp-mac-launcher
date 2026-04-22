import Darwin
import Foundation

/// Diagnose: **stderr** (kurz, synchron) + `AppPaths.logFilesDirectory/launcher-load-trace.log` (asynchron).
/// Wichtig: kein `DispatchQueue.sync` + `FileManager` vom **MainThread** (z. B. Menü-Rebuild) — das kann mit Main-Queue-Rückrufen **deadlocken** und die App beenden lassen.
enum LaunchLoadTrace {
    private static let fileQueue = DispatchQueue(label: "de.bizolution.trade-erp-launcher.launchloadtrace.file", qos: .utility)

    static func preview(_ s: String, max: Int = 280) -> String {
        let t = s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "\\n")
        if t.count <= max { return t }
        return String(t.prefix(max)) + "…(+\(s.count - max) Zeichen)"
    }

    static func log(_ message: String) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let line = "[\(f.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            _ = write(STDERR_FILENO, base, raw.count)
        }
        let dataCopy = data
        fileQueue.async {
            let dir = AppPaths.logFilesDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("launcher-load-trace.log", isDirectory: false)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: dataCopy, attributes: nil)
            } else if let fh = try? FileHandle(forWritingTo: fileURL) {
                defer { try? fh.close() }
                fh.seekToEndOfFile()
                try? fh.write(contentsOf: dataCopy)
            }
        }
    }
}
