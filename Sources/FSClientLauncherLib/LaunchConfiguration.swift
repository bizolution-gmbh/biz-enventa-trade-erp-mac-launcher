import Foundation

enum LaunchConfiguration {
    /// Brücken-URL, damit ein **Lesezeichen / Verknüpfung** die echte **http(s)**-Definitions-URL an den Launcher übergibt (Browser startet keine fremden http-Links in Apps).
    /// Form: `fsclientlauncher:jnlp?url=` + **eine** URL-Kodierung der Ziel-URL (`https%3A%2F%2F…%2Fapi%2Fjnlp%3F…`).
    static func embeddedHttpURLFromFsClientLauncherJnlpBridge(_ raw: String) -> String? {
        let t = sanitizeHttpURLUserInput(raw)
        guard t.lowercased().hasPrefix("fsclientlauncher:") else { return nil }
        var rest = String(t.dropFirst("fsclientlauncher:".count))
        if rest.hasPrefix("//") {
            rest = String(rest.dropFirst(2))
        }
        guard let qIdx = rest.firstIndex(of: "?") else { return nil }
        let pathPart = String(rest[..<qIdx]).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard pathPart == "jnlp" else { return nil }
        let query = String(rest[rest.index(after: qIdx)...])
        let items = URLComponents(string: "d://h?" + query)?.queryItems ?? []
        let keys = ["url", "u", "target", "href", "jnlp", "jnlpurl"]
        for key in keys {
            guard let v = items.first(where: { $0.name.lowercased() == key })?.value else { continue }
            let decoded = v.removingPercentEncoding ?? v
            let d = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            let l = d.lowercased()
            if l.hasPrefix("http://") || l.hasPrefix("https://") {
                return d
            }
        }
        return nil
    }

    /// Prüft, ob `fsclientlauncher:launch?…` mit den gleichen Regeln wie beim Start geparst werden kann.
    static func isParsableFsClientLauncherLaunchURI(_ raw: String) -> Bool {
        let t0 = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t0.range(of: "fsclientlauncher:", options: .caseInsensitive) else { return false }
        let t = "fsclientlauncher:" + String(t0[r.upperBound...])
        return (try? parseFsClientLauncherURI(t)) != nil
    }

    /// `http(s)://…/…/api/jnlp?…` oder `…/api/fsclient?…` — Web liefert auf dem Mac oft keine `.fsclient`-Datei; der Server antwortet stattdessen mit **302 → fsclientlauncher:launch?…**.
    static func shouldOfferLauncherBridge(forHttpShortcut raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.lowercased().hasPrefix("fsclientlauncher:") else { return false }
        return fsClientLauncherLaunchURLFromWebDefinitionHTTP(t) != nil
    }

    /// Baut `fsclientlauncher:launch?title=…&broker=…&theme=…&language=…&lookAndFeel=…` wie bei einer typischen Server-Weiterleitung (`lang`→`language`, `themeid`→`theme`, `metal`→`lookAndFeel`).
    static func fsClientLauncherLaunchURLFromWebDefinitionHTTP(_ raw: String) -> String? {
        let cleaned = stripLeadingGarbageBeforeHTTPScheme(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        let low = cleaned.lowercased()
        guard low.hasPrefix("http://") || low.hasPrefix("https://") else { return nil }
        guard let u = resolveHttpURLFromUserString(cleaned) ?? httpRemoteAPIURL(from: cleaned) else { return nil }
        let pathDec = u.path.removingPercentEncoding ?? u.path
        guard let apiRange = pathDec.range(of: "/api/", options: .caseInsensitive) else { return nil }
        let afterApi = pathDec[apiRange.upperBound...].lowercased()
        guard afterApi.hasPrefix("jnlp") || afterApi.hasPrefix("fsclient") else { return nil }
        let basePath = String(pathDec[..<apiRange.lowerBound])
        guard basePath != "/", basePath.count > 1 else { return nil }
        let slug = (basePath as NSString).lastPathComponent
        guard !slug.isEmpty else { return nil }
        guard var brokerComp = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        let brokerPath = basePath.hasSuffix("/") ? basePath : basePath + "/"
        brokerComp.path = brokerPath
        brokerComp.query = nil
        brokerComp.fragment = nil
        guard let brokerURL = brokerComp.url?.absoluteString else { return nil }
        let qItems = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            qItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let language = q("lang") ?? "de"
        let theme = q("themeid") ?? q("themename") ?? "DefaultID"
        let lookAndFeel = q("metal") ?? "1"
        let noDomain = q("nodomainauth")
        // Strikte Kodierung der Query-Werte (wie typische 302-Location), damit u. a. „:“ und „/“ im Broker sicher escaped sind.
        let formValueAllowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let enc: (String) -> String = { s in
            s.addingPercentEncoding(withAllowedCharacters: formValueAllowed) ?? s
        }
        var pairs: [String] = [
            "\(ApiFsClientKeys.title)=\(enc(slug))",
            "\(ApiFsClientKeys.broker)=\(enc(brokerURL))",
            "\(ApiFsClientKeys.theme)=\(enc(theme))",
            "\(ApiFsClientKeys.language)=\(enc(language))",
            "\(ApiFsClientKeys.lookAndFeel)=\(enc(lookAndFeel))",
        ]
        if let nd = noDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !nd.isEmpty {
            pairs.append("\(ApiFsClientKeys.noDomainAuth)=\(enc(nd))")
        }
        return "fsclientlauncher:launch?" + pairs.joined(separator: "&")
    }

    /// Lädt **.fsclient**-JSON von einer geparsten **http(s)**-URL, legt sie temporär ab und dekodiert wie eine lokale Datei.
    /// Der Server kann mit **302** auf `fsclientlauncher:launch?…` weiterleiten — das wird wie ein direkter Launcher-Aufruf verarbeitet.
    private static func loadFromRemoteFsClientDownloadURL(
        remote: URL,
        displayArgument: String,
        persistShortcutAfterLaunch: Bool
    ) async throws -> ParsedFsClientLaunch {
        LaunchLoadTrace.log("loadFromRemoteFsClientDownloadURL: GET \(LaunchLoadTrace.preview(remote.absoluteString))")
        switch try await downloadFsClientDefinition(from: remote) {
        case .redirectToFsClientLauncher(let location):
            LaunchLoadTrace.log(
                "loadFromRemoteFsClientDownloadURL: HTTP-Redirect → fsclientlauncher (intern): \(LaunchLoadTrace.preview(location))"
            )
            return try await loadFromFsClientLauncherString(
                location,
                originalArgument: displayArgument,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        case .jsonData(let data):
            let tempURL = try writeFsClientJsonToTemporaryFile(data)
            let fromFile = try Data(contentsOf: tempURL)
            let client = try decodeFsClient(from: fromFile)
            let path = (tempURL.path as NSString).standardizingPath
            return ParsedFsClientLaunch(
                client: client,
                jsonData: data,
                openedFromDirectLocalFile: true,
                localFilePath: path,
                originalArgument: displayArgument,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        }
    }

    // MARK: - Eingabeauflösung (ein Pfad für alle Quellen)

    /// Erkennt **remote .fsclient-Definition** anhand der kanonischen `URL` (ohne erneutes Parsen des Strings).
    private static func urlLooksLikeRemoteFsClientDefinition(_ u: URL) -> Bool {
        let pathDec = (u.path.removingPercentEncoding ?? u.path).lowercased()
        let abs = u.absoluteString.lowercased()
        if pathDec.contains("/api/fsclient") || abs.contains("/api/fsclient") { return true }
        let blob = (u.path + "?" + (u.query ?? "")).lowercased() + abs
        return blob.contains("fsclient")
    }

    /// **Definitions-URL mit „jnlp“ im Pfad** (z. B. `/api/jnlp`) anhand von `URL`-Pfad und `-absoluteString`.
    private static func urlLooksLikeRemoteJnlpPage(_ u: URL) -> Bool {
        let pathDec = (u.path.removingPercentEncoding ?? u.path).lowercased()
        let abs = u.absoluteString.lowercased()
        if pathDec.contains("/api/jnlp") { return true }
        if pathDec.hasSuffix("/jnlp") { return true }
        let last = (pathDec as NSString).lastPathComponent
        if last == "jnlp" || last.hasPrefix("jnlp.") { return true }
        if abs.range(of: #"[/]api[/._-]?jnlp"#, options: .regularExpression) != nil { return true }
        if abs.range(of: #"[/]jnlp\?"#, options: .regularExpression) != nil { return true }
        let qlow = (u.query ?? "").lowercased()
        if qlow.contains("api/jnlp") { return true }
        let segs = pathDec.split(separator: "/").map(String.init)
        if segs.contains(where: { $0 == "jnlp" || $0.hasPrefix("jnlp.") }) { return true }
        return false
    }

    /// **Ein** Ablauf für jede gültige **http(s)-URL** (Tray-String, argv, `open urls:`).
    private static func loadHTTPURLConnection(
        url: URL,
        displayArgument: String,
        persistShortcutAfterLaunch: Bool
    ) async throws -> ParsedFsClientLaunch {
        let host = url.host ?? "(nil)"
        let sch = url.scheme ?? "(nil)"
        let fsTarget: URL
        if urlLooksLikeRemoteJnlpPage(url) {
            fsTarget = rewriteRemoteJnlpDefinitionURLToFsClientAPI(url)
            LaunchLoadTrace.log(
                "loadHTTPURLConnection: jnlp-Pfad → fsclient-URL \(LaunchLoadTrace.preview(fsTarget.absoluteString))"
            )
        } else if let jnlpLike = jnlpRemoteAPIURL(from: displayArgument) ?? jnlpRemoteAPIURL(from: url.absoluteString) {
            fsTarget = rewriteRemoteJnlpDefinitionURLToFsClientAPI(jnlpLike)
            LaunchLoadTrace.log(
                "loadHTTPURLConnection: jnlpRemoteAPIURL-Fallback → fsclient-URL \(LaunchLoadTrace.preview(fsTarget.absoluteString))"
            )
        } else {
            fsTarget = url
        }
        LaunchLoadTrace.log(
            "loadHTTPURLConnection: scheme=\(sch) host=\(host) path=\(url.path) looksFsClient=\(urlLooksLikeRemoteFsClientDefinition(fsTarget)) display=\(LaunchLoadTrace.preview(displayArgument))"
        )
        guard let schL = url.scheme?.lowercased(), schL == "http" || schL == "https", url.host != nil else {
            LaunchLoadTrace.log("loadHTTPURLConnection: invalidURI — kein http(s) oder kein Host (scheme=\(sch) host=\(host))")
            throw LaunchError.invalidURI(displayArgument)
        }
        if urlLooksLikeRemoteFsClientDefinition(fsTarget) {
            return try await loadFromRemoteFsClientDownloadURL(
                remote: fsTarget,
                displayArgument: displayArgument,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        }
        LaunchLoadTrace.log(
            "loadHTTPURLConnection: invalidURI — keine passende Remote-Definition. absolute=\(LaunchLoadTrace.preview(url.absoluteString))"
        )
        throw LaunchError.invalidURI(displayArgument)
    }

    private static func loadLocalFileLaunch(trimmedArgument: String, persistShortcutAfterLaunch: Bool) async throws -> ParsedFsClientLaunch {
        LaunchLoadTrace.log("loadLocalFileLaunch: \(LaunchLoadTrace.preview(trimmedArgument))")
        let lower = trimmedArgument.lowercased()
        if lower.hasSuffix(".jnlp") {
            LaunchLoadTrace.log("loadLocalFileLaunch: .jnlp wird nicht unterstützt")
            throw LaunchError.invalidURI(trimmedArgument)
        }
        let fileURL = resolveLocalFileURL(from: trimmedArgument)
        LaunchLoadTrace.log("loadLocalFileLaunch: lese .fsclient/JSON von \(LaunchLoadTrace.preview(fileURL.path))")
        let data = try Data(contentsOf: fileURL)
        let client = try decodeFsClient(from: data)
        let path = (fileURL.path as NSString).standardizingPath
        return ParsedFsClientLaunch(
            client: client,
            jsonData: data,
            openedFromDirectLocalFile: true,
            localFilePath: path,
            originalArgument: trimmedArgument,
            persistShortcutAfterLaunch: persistShortcutAfterLaunch
        )
    }

    /// Von `application(_:open urls:)` — nutzt dieselbe HTTP-Logik wie Zeichenketten-Starts, aber **ohne** `absoluteString` → erneutes Parsen für http(s).
    static func load(systemOpenURL url: URL, persistShortcutAfterLaunch: Bool = true) async throws -> ParsedFsClientLaunch {
        LaunchLoadTrace.log("load(systemOpenURL): \(LaunchLoadTrace.preview(url.absoluteString)) isFileURL=\(url.isFileURL)")
        if url.isFileURL {
            return try await loadLocalFileLaunch(trimmedArgument: url.path, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        if url.scheme?.lowercased() == "fsclientlauncher" {
            return try await load(firstArgument: url.absoluteString, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        guard let sch = url.scheme?.lowercased(), sch == "http" || sch == "https" else {
            LaunchLoadTrace.log("load(systemOpenURL): invalidURI — Schema nicht http(s): \(url.scheme ?? "nil")")
            throw LaunchError.invalidURI(url.absoluteString)
        }
        return try await loadHTTPURLConnection(
            url: url,
            displayArgument: url.absoluteString,
            persistShortcutAfterLaunch: persistShortcutAfterLaunch
        )
    }

    /// Erster CLI-Parameter: `fsclientlauncher:launch?…`, **http(s)-URL** zu einer `.fsclient`-API, oder Pfad zu JSON (wie Windows `LaunchService.Init`).
    static func load(firstArgument: String, persistShortcutAfterLaunch: Bool = true) async throws -> ParsedFsClientLaunch {
        LaunchLoadTrace.log("load(firstArgument): Länge=\(firstArgument.count) Vorschau=\(LaunchLoadTrace.preview(firstArgument))")
        let wsOnly = firstArgument.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = stripLeadingGarbageBeforeHTTPScheme(wsOnly)
        if let inner = embeddedHttpURLFromFsClientLauncherJnlpBridge(trimmed) {
            return try await load(firstArgument: inner, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        let tl = trimmed.lowercased()
        if tl.hasPrefix("fsclientlauncher:") {
            return try await loadFromFsClientLauncherString(
                trimmed,
                originalArgument: trimmed,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        }
        if tl.hasPrefix("http://") || tl.hasPrefix("https://") {
            let rHttp = resolveHttpURLFromUserString(trimmed)
            let rRemote = httpRemoteAPIURL(from: trimmed)
            let rLenient = parseLenientHTTPURL(trimmed)
            let rLenientWs = parseLenientHTTPURL(wsOnly.trimmingCharacters(in: .whitespacesAndNewlines))
            let u = rHttp ?? rRemote ?? rLenient ?? rLenientWs
            LaunchLoadTrace.log(
                "load(firstArgument): http-Auflösung resolveHttpURL=\(rHttp.map { LaunchLoadTrace.preview($0.absoluteString) } ?? "nil") httpRemoteAPI=\(rRemote.map { LaunchLoadTrace.preview($0.absoluteString) } ?? "nil") lenient=\(rLenient.map { LaunchLoadTrace.preview($0.absoluteString) } ?? "nil")"
            )
            guard let u,
                  let sch = u.scheme?.lowercased(), sch == "http" || sch == "https",
                  u.host != nil else {
                LaunchLoadTrace.log(
                    "load(firstArgument): invalidURI — http(s) konnte nicht zu URL mit Host aufgelöst werden. trimmed=\(LaunchLoadTrace.preview(trimmed))"
                )
                throw LaunchError.invalidURI(trimmed)
            }
            return try await loadHTTPURLConnection(
                url: u,
                displayArgument: trimmed,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        }
        LaunchLoadTrace.log("load(firstArgument): kein http(s)-Präfix — lokaler Pfad / Datei-Zweig")
        return try await loadLocalFileLaunch(trimmedArgument: trimmed, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
    }

    // MARK: - fsclientlauncher:

    private static func parseFsClientLauncherURI(_ firstArgument: String) throws -> ApiFsClient {
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

    private static func jsonDataForPersistence(from client: ApiFsClient) throws -> Data {
        let obj = client.args as [String: Any]
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: - Remote (http/https)

    /// Schreibt heruntergeladene **.fsclient**-JSON in eine temporäre Datei (wie Doppelklick auf eine lokale Definition).
    private static func writeFsClientJsonToTemporaryFile(_ data: Data) throws -> URL {
        let name = "fsclient-remote-\(UUID().uuidString).fsclient"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Baut aus einer **http(s)-Definitions-URL** mit **jnlp** im Pfad dieselbe URL mit `…/api/fsclient…` (ohne lokale `.jnlp`-Datei oder XML).
    private static func rewriteRemoteJnlpDefinitionURLToFsClientAPI(_ url: URL) -> URL {
        guard var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var path = comp.path
        if path.range(of: "/api/jnlp", options: .caseInsensitive) != nil {
            path = path.replacingOccurrences(of: "/api/jnlp", with: "/api/fsclient", options: .caseInsensitive)
        } else if path.range(of: "/jnlp", options: .caseInsensitive) != nil {
            path = path.replacingOccurrences(of: "/jnlp", with: "/fsclient", options: .caseInsensitive)
        } else {
            path = path.replacingOccurrences(of: "jnlp", with: "fsclient", options: .caseInsensitive)
        }
        comp.path = path
        if var items = comp.queryItems {
            items.removeAll { $0.name.caseInsensitiveCompare("file") == .orderedSame }
            comp.queryItems = items.isEmpty ? nil : items
        }
        return comp.url ?? url
    }

    private enum FsClientDefinitionDownloadResult {
        case jsonData(Data)
        /// Exakte `Location`-Zeile (meist `fsclientlauncher:launch?…`), nach Normalisierung von `fsclientlauncher://`.
        case redirectToFsClientLauncher(location: String)
    }

    /// Lädt Rohbytes (JSON) oder erkennt **302 → fsclientlauncher:** (Server startet den Launcher so).
    private static func downloadFsClientDefinition(from url: URL) async throws -> FsClientDefinitionDownloadResult {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.default
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let delegate = FsClientDefinitionSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            LaunchLoadTrace.log(
                "downloadFsClientDefinition: Netzwerkfehler \(String(describing: type(of: error))) — \(error.localizedDescription) url=\(LaunchLoadTrace.preview(url.absoluteString))"
            )
            throw mapFsClientDownloadTransportError(url: url, error: error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw LaunchError.fsclientRemoteHTTP(-1)
        }
        if (200 ... 299).contains(http.statusCode) {
            return .jsonData(data)
        }
        if (300 ... 399).contains(http.statusCode) {
            if let raw = http.value(forHTTPHeaderField: "Location")?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let locNorm = normalizeLauncherRedirectLocation(raw)
                LaunchLoadTrace.log(
                    "downloadFsClientDefinition: HTTP \(http.statusCode) für \(LaunchLoadTrace.preview(url.absoluteString)) — Location=\(LaunchLoadTrace.preview(locNorm))"
                )
                let locLow = locNorm.lowercased()
                if locLow.hasPrefix("fsclientlauncher:") {
                    return .redirectToFsClientLauncher(location: locNorm)
                }
            } else {
                LaunchLoadTrace.log(
                    "downloadFsClientDefinition: HTTP \(http.statusCode) ohne Location für \(LaunchLoadTrace.preview(url.absoluteString))"
                )
            }
            throw LaunchError.fsclientRemoteHTTP(http.statusCode)
        }
        LaunchLoadTrace.log("downloadFsClientDefinition: HTTP \(http.statusCode) für \(LaunchLoadTrace.preview(url.absoluteString))")
        throw LaunchError.fsclientRemoteHTTP(http.statusCode)
    }

    /// `fsclientlauncher://launch?…` aus Location-Header in die Form bringen, die `parseFsClientLauncherURI` erwartet.
    private static func normalizeLauncherRedirectLocation(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("fsclientlauncher://"),
           let r = s.range(of: "fsclientlauncher://", options: .caseInsensitive) {
            s = "fsclientlauncher:" + String(s[r.upperBound...])
        }
        return s
    }

    /// Direktes `fsclientlauncher:…` oder per **HTTP-302-Location** (gleiche Parser wie CLI/Tray).
    private static func loadFromFsClientLauncherString(
        _ trimmed: String,
        originalArgument: String,
        persistShortcutAfterLaunch: Bool
    ) async throws -> ParsedFsClientLaunch {
        let t0 = normalizeLauncherRedirectLocation(trimmed.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let r = t0.range(of: "fsclientlauncher:", options: .caseInsensitive) else {
            throw LaunchError.invalidFsClientLauncherURI
        }
        let t = "fsclientlauncher:" + String(t0[r.upperBound...])
        if let inner = embeddedHttpURLFromFsClientLauncherJnlpBridge(t) {
            return try await load(firstArgument: inner, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        var rest = String(t.dropFirst("fsclientlauncher:".count))
        if rest.hasPrefix("//") {
            rest = String(rest.dropFirst(2))
        }
        if let qIdx = rest.firstIndex(of: "?") {
            let pathPart = String(rest[..<qIdx]).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            if pathPart == "jnlp" {
                throw LaunchError.invalidFsClientLauncherURI
            }
        }
        let client = try parseFsClientLauncherURI(t)
        let data = try jsonDataForPersistence(from: client)
        return ParsedFsClientLaunch(
            client: client,
            jsonData: data,
            openedFromDirectLocalFile: false,
            localFilePath: nil,
            originalArgument: originalArgument,
            persistShortcutAfterLaunch: persistShortcutAfterLaunch
        )
    }

    private static func mapFsClientDownloadTransportError(url: URL, error: Error) -> LaunchError {
        if let u = error as? URLError {
            var lines: [String] = ["URLError \(u.code.rawValue): \(u.localizedDescription)"]
            if let fail = u.failureURLString, !fail.isEmpty {
                lines.append("Zuletzt betroffene URL: \(fail)")
            }
            switch u.code {
            case .unsupportedURL:
                lines.append(
                    "Hinweis: Oft eine HTTP-Weiterleitung (301/302) mit ungültiger oder nicht-http(s)-„Location“ (z. B. interner Link), die macOS nicht laden kann."
                )
            case .cannotFindHost, .dnsLookupFailed:
                lines.append("Hinweis: Hostname/DNS prüfen — VPN oder Firmen-DNS nötig?")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut:
                lines.append("Hinweis: Netzwerkverbindung, Firewall und ggf. HTTP-Proxy in den macOS-Systemeinstellungen prüfen.")
            default:
                lines.append("Hinweis: Firmen-Proxy, Filter und VPN prüfen.")
            }
            return .fsclientDefinitionDownloadFailed(url: url.absoluteString, reason: lines.joined(separator: "\n"))
        }
        let ns = error as NSError
        let reason = "\(ns.domain) Code \(ns.code): \(ns.localizedDescription)"
        return .fsclientDefinitionDownloadFailed(url: url.absoluteString, reason: reason)
    }

    // MARK: - Lokale Datei

    private static func resolveLocalFileURL(from trimmed: String) -> URL {
        if trimmed.hasPrefix("file:"), let u = URL(string: trimmed) {
            return u
        }
        return URL(fileURLWithPath: trimmed, isDirectory: false)
    }

    // MARK: - JSON

    private static func decodeFsClient(from data: Data) throws -> ApiFsClient {
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

private final class FsClientDefinitionSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        HTTPOutboundRedirectPolicy.respondToRedirect(
            context: "downloadFsClientDefinition",
            response: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }
}
