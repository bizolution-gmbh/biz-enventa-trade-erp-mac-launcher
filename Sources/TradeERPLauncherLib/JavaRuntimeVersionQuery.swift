import Foundation

/// Erste Zeile von `java -version` (Stderr/Stdout) — bewusst außerhalb des MainActor, damit `Task.detached` Swift-6-konform bleibt.
enum JavaRuntimeVersionQuery {
    private static let maxVersionLineCharacters = 200

    static func firstLine(javaExecutable: URL) -> String? {
        let p = Process()
        p.executableURL = javaExecutable
        p.arguments = ["-version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let first = raw.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? raw
        return String(first.prefix(maxVersionLineCharacters))
    }
}
