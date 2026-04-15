import Foundation

/// Lädt `api/jardownload` bzw. bei HTTP 404 den Fallback `JarDownload.ashx` — wie `LaunchService.DownloadBrokerInfo`.
enum BrokerFetcher {
    static func downloadJarDownloadPayload(brokerBase: String) async throws -> Data {
        let brokerURL = try normalizedBrokerURL(brokerBase)
        let primary = brokerURL.appendingPathComponent("api/jardownload")
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
        if !s.contains("://") {
            s = "https://" + s
        }
        guard let c = URLComponents(string: s) else {
            throw LaunchError.invalidURI(brokerBase)
        }
        if c.path == "/" || c.path.isEmpty { /* ok */ }
        guard let u = c.url else {
            throw LaunchError.invalidURI(brokerBase)
        }
        return u
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
