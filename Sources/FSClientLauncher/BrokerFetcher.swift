import Foundation

/// Lädt `api/jardownload` bzw. bei HTTP 404 den Fallback `JarDownload.ashx` — wie `LaunchService.DownloadBrokerInfo`.
enum BrokerFetcher {
    static func downloadJarDownloadPayload(brokerBase: String) async throws -> Data {
        let brokerURL = try normalizedBrokerURL(brokerBase)
        return try await attemptJarDownload(fromBrokerRoot: brokerURL)
    }

    /// Lädt zuerst `api/jardownload`, bei HTTP 404 `JarDownload.ashx` (gleiche Broker-Basis).
    private static func attemptJarDownload(fromBrokerRoot brokerURL: URL) async throws -> Data {
        let primary = brokerURL.appendingPathComponent("api/jardownload")
        LaunchLoadTrace.log(
            "BrokerFetcher: brokerRoot=\(LaunchLoadTrace.preview(brokerURL.absoluteString)) GET \(LaunchLoadTrace.preview(primary.absoluteString))"
        )
        let (data, response) = try await dataRequest(url: primary)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            let fallback = brokerURL.appendingPathComponent("JarDownload.ashx")
            let (data2, response2) = try await dataRequest(url: fallback)
            guard let http2 = response2 as? HTTPURLResponse, (200 ... 299).contains(http2.statusCode) else {
                throw LaunchError.brokerHTTP((response2 as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return data2
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw LaunchError.brokerHTTP((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    /// Gleiche Normalisierung wie für Broker-Download — für JAR-Basis-URL und Splash nutzen.
    static func normalizedBrokerURL(_ brokerBase: String) throws -> URL {
        var s = brokerBase.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "")
        if let r = s.range(of: "https://", options: .caseInsensitive) {
            s = String(s[r.lowerBound...])
        } else if let r = s.range(of: "http://", options: .caseInsensitive) {
            s = String(s[r.lowerBound...])
        }
        if !s.contains("://") {
            s = "https://" + s
        }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), (scheme == "http" || scheme == "https"), u.host != nil {
            return brokerRootStrippingApiDefinitionURL(u)
        }
        guard let c = URLComponents(string: s) else {
            throw LaunchError.invalidBrokerURI(brokerBase)
        }
        if c.path == "/" || c.path.isEmpty { /* ok */ }
        if let u = c.url {
            return brokerRootStrippingApiDefinitionURL(u)
        }
        if let qIdx = s.firstIndex(of: "?") {
            let head = String(s[..<qIdx])
            let query = String(s[s.index(after: qIdx)...])
            let allowed = CharacterSet.urlQueryAllowed
            if let qEnc = query.addingPercentEncoding(withAllowedCharacters: allowed),
               let u = URL(string: head + "?" + qEnc), u.host != nil {
                return brokerRootStrippingApiDefinitionURL(u)
            }
        }
        throw LaunchError.invalidBrokerURI(brokerBase)
    }

    /// Manche `.fsclient`-Dateien tragen im Feld `broker` die **komplette** Definitions-URL (`…/api/fsclient?…` / `…/api/jnlp?…`).
    /// Für `…/api/jardownload` ist aber der **Anwendungsstamm** nötig (alles vor `/api/fsclient` bzw. `/api/jnlp`) — sonst entsteht z. B. `…/api/fsclient/api/jardownload` → HTTP 404.
    private static func brokerRootStrippingApiDefinitionURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let path = components.path.removingPercentEncoding ?? components.path
        let markers = ["/api/fsclient", "/api/jnlp"]
        for m in markers {
            guard let r = path.range(of: m, options: .caseInsensitive) else { continue }
            let tail = path[r.upperBound...]
            if !tail.isEmpty {
                let c0 = tail[tail.startIndex]
                if c0 != "?" && c0 != "/" { continue }
            }
            var base = String(path[..<r.lowerBound])
            while base.hasSuffix("/"), base.count > 1 {
                base.removeLast()
            }
            components.path = base.isEmpty ? "/" : base
            components.query = nil
            components.fragment = nil
            return components.url ?? url
        }
        return url
    }

    private static func dataRequest(url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let config = urlSessionConfiguration()
        let session = URLSession(configuration: config)
        return try await session.data(for: req)
    }

    /// Gemeinsame `URLSessionConfiguration` für Broker- und JAR-Downloads (System-Proxy wie in den macOS-Netzwerkeinstellungen).
    static func urlSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.waitsForConnectivity = false
        // Kein connectionProxyDictionary: leeres Dictionary kann Verbindungen hinter Firmenproxy stören;
        // die JVM-Proxy-Steuerung bleibt über -Djava.net.useSystemProxies in LaunchCoordinator.
        return config
    }
}
