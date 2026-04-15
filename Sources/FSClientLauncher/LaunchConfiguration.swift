import Foundation

enum LaunchConfiguration {
    /// Erster CLI-Parameter: `fsclientlauncher:launch?…` oder Pfad zu JSON (wie `LaunchService.Init` der Windows-App).
    static func parse(firstArgument: String) throws -> ApiFsClient {
        if firstArgument.lowercased().hasPrefix("fsclientlauncher:") {
            var withoutScheme = firstArgument.dropFirst("fsclientlauncher:".count)
            if withoutScheme.hasPrefix("//") {
                withoutScheme = withoutScheme.dropFirst(2)
            }
            guard let qIndex = withoutScheme.firstIndex(of: "?") else {
                throw LaunchError.invalidFsClientLauncherURI
            }
            let pathPart = withoutScheme[..<qIndex]
            guard pathPart.lowercased() == "launch" else {
                throw LaunchError.invalidFsClientLauncherURI
            }
            let query = String(withoutScheme[withoutScheme.index(after: qIndex)...])
            let items = URLComponents(string: "dummy://h?" + query)?.queryItems ?? []
            var dict: [String: String] = [:]
            for item in items {
                dict[item.name] = item.value ?? ""
            }
            return try ApiFsClient(args: dict)
        }
        let fileURL: URL
        if firstArgument.hasPrefix("file:"), let u = URL(string: firstArgument) {
            fileURL = u
        } else {
            fileURL = URL(fileURLWithPath: firstArgument, isDirectory: false)
        }
        let data = try Data(contentsOf: fileURL)
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let dict = obj.compactMapValues { $0 as? String }
            return try ApiFsClient(args: dict)
        } catch let e as LaunchError {
            throw e
        } catch {
            throw LaunchError.invalidJSONFile(error)
        }
    }
}
