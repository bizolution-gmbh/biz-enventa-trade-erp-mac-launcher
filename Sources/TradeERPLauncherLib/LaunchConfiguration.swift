import Foundation

enum LaunchConfiguration {
    // MARK: - Brücken-URLs (öffentliche Hilfen)

    /// Brücken-URL, damit ein **Lesezeichen / Verknüpfung** die echte **http(s)**-Definitions-URL an den Launcher übergibt (Browser startet keine fremden http-Links in Apps).
    /// Form: `fsclientlauncher:jnlp?url=` + **eine** URL-Kodierung der Ziel-URL (`https%3A%2F%2F…%2Fapi%2Fjnlp%3F…`).
    static func embeddedHttpURLFromLauncherJnlpBridge(_ raw: String) -> String? {
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
    static func isParsableLauncherLaunchURI(_ raw: String) -> Bool {
        let t0 = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t0.range(of: "fsclientlauncher:", options: .caseInsensitive) else { return false }
        let t = "fsclientlauncher:" + String(t0[r.upperBound...])
        return (try? parseLauncherLaunchURI(t)) != nil
    }

    /// `http(s)://…/…/api/jnlp?…` oder `…/api/fsclient?…` — Web liefert auf dem Mac oft keine `.fsclient`-Datei; der Server antwortet stattdessen mit **302 → fsclientlauncher:launch?…**.
    static func shouldOfferLauncherBridge(forHttpShortcut raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.lowercased().hasPrefix("fsclientlauncher:") else { return false }
        return launcherLaunchURLFromWebDefinitionHTTP(t) != nil
    }

    /// Baut `fsclientlauncher:launch?title=…&broker=…&theme=…&language=…&lookAndFeel=…` wie bei einer typischen Server-Weiterleitung (`lang`→`language`, `themeid`→`theme`, `metal`→`lookAndFeel`).
    static func launcherLaunchURLFromWebDefinitionHTTP(_ raw: String) -> String? {
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
            "\(LaunchParameterKey.title)=\(enc(slug))",
            "\(LaunchParameterKey.broker)=\(enc(brokerURL))",
            "\(LaunchParameterKey.theme)=\(enc(theme))",
            "\(LaunchParameterKey.language)=\(enc(language))",
            "\(LaunchParameterKey.lookAndFeel)=\(enc(lookAndFeel))",
        ]
        if let nd = noDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !nd.isEmpty {
            pairs.append("\(LaunchParameterKey.noDomainAuth)=\(enc(nd))")
        }
        return "fsclientlauncher:launch?" + pairs.joined(separator: "&")
    }

    /// Lädt **.fsclient**-JSON von einer geparsten **http(s)**-URL, legt sie temporär ab und dekodiert wie eine lokale Datei.
    /// Der Server kann mit **302** auf `fsclientlauncher:launch?…` weiterleiten — das wird wie ein direkter Launcher-Aufruf verarbeitet.
    private static func loadFromRemoteDefinitionDownloadURL(
        remote: URL,
        displayArgument: String,
        persistShortcutAfterLaunch: Bool
    ) async throws -> ParsedLaunchInput {
        LaunchLoadTrace.log("loadFromRemoteDefinitionDownloadURL: GET \(LaunchLoadTrace.preview(remote.absoluteString))")
        switch try await downloadLauncherDefinition(from: remote) {
        case .redirectToLauncherScheme(let location):
            LaunchLoadTrace.log(
                "loadFromRemoteDefinitionDownloadURL: HTTP-Redirect → fsclientlauncher (intern): \(LaunchLoadTrace.preview(location))"
            )
            return try await loadFromLauncherURIString(
                location,
                originalArgument: displayArgument,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
        case .jsonData(let data):
            let tempURL = try writeLauncherDefinitionJsonToTemporaryFile(data)
            let fromFile = try Data(contentsOf: tempURL)
            let parameters = try decodeLaunchParameters(from: fromFile)
            let path = (tempURL.path as NSString).standardizingPath
            return ParsedLaunchInput(
                parameters: parameters,
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
    private static func urlLooksLikeRemoteClientDefinition(_ u: URL) -> Bool {
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
    ) async throws -> ParsedLaunchInput {
        let host = url.host ?? "(nil)"
        let sch = url.scheme ?? "(nil)"
        let fsTarget: URL
        if urlLooksLikeRemoteJnlpPage(url) {
            fsTarget = rewriteRemoteJnlpDefinitionURLToClientAPI(url)
            LaunchLoadTrace.log(
                "loadHTTPURLConnection: jnlp-Pfad → fsclient-URL \(LaunchLoadTrace.preview(fsTarget.absoluteString))"
            )
        } else if let jnlpLike = jnlpRemoteAPIURL(from: displayArgument) ?? jnlpRemoteAPIURL(from: url.absoluteString) {
            fsTarget = rewriteRemoteJnlpDefinitionURLToClientAPI(jnlpLike)
            LaunchLoadTrace.log(
                "loadHTTPURLConnection: jnlpRemoteAPIURL-Fallback → fsclient-URL \(LaunchLoadTrace.preview(fsTarget.absoluteString))"
            )
        } else {
            fsTarget = url
        }
        LaunchLoadTrace.log(
            "loadHTTPURLConnection: scheme=\(sch) host=\(host) path=\(url.path) looksRemoteDefinition=\(urlLooksLikeRemoteClientDefinition(fsTarget)) display=\(LaunchLoadTrace.preview(displayArgument))"
        )
        guard let schL = url.scheme?.lowercased(), schL == "http" || schL == "https", url.host != nil else {
            LaunchLoadTrace.log("loadHTTPURLConnection: invalidURI — kein http(s) oder kein Host (scheme=\(sch) host=\(host))")
            throw LaunchError.invalidURI(displayArgument)
        }
        if urlLooksLikeRemoteClientDefinition(fsTarget) {
            return try await loadFromRemoteDefinitionDownloadURL(
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

    private static func loadLocalFileLaunch(trimmedArgument: String, persistShortcutAfterLaunch: Bool) async throws -> ParsedLaunchInput {
        LaunchLoadTrace.log("loadLocalFileLaunch: \(LaunchLoadTrace.preview(trimmedArgument))")
        let lower = trimmedArgument.lowercased()
        if lower.hasSuffix(".jnlp") {
            LaunchLoadTrace.log("loadLocalFileLaunch: .jnlp wird nicht unterstützt")
            throw LaunchError.invalidURI(trimmedArgument)
        }
        let fileURL = resolveLocalFileURL(from: trimmedArgument)
        LaunchLoadTrace.log("loadLocalFileLaunch: lese .fsclient/JSON von \(LaunchLoadTrace.preview(fileURL.path))")
        let data = try Data(contentsOf: fileURL)
        let parameters = try decodeLaunchParameters(from: data)
        let path = (fileURL.path as NSString).standardizingPath
        return ParsedLaunchInput(
            parameters: parameters,
            jsonData: data,
            openedFromDirectLocalFile: true,
            localFilePath: path,
            originalArgument: trimmedArgument,
            persistShortcutAfterLaunch: persistShortcutAfterLaunch
        )
    }

    /// Von `application(_:open urls:)` — nutzt dieselbe HTTP-Logik wie Zeichenketten-Starts, aber **ohne** `absoluteString` → erneutes Parsen für http(s).
    static func load(systemOpenURL url: URL, persistShortcutAfterLaunch: Bool = true) async throws -> ParsedLaunchInput {
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
    static func load(firstArgument: String, persistShortcutAfterLaunch: Bool = true) async throws -> ParsedLaunchInput {
        LaunchLoadTrace.log("load(firstArgument): Länge=\(firstArgument.count) Vorschau=\(LaunchLoadTrace.preview(firstArgument))")
        let wsOnly = firstArgument.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = stripLeadingGarbageBeforeHTTPScheme(wsOnly)
        if let inner = embeddedHttpURLFromLauncherJnlpBridge(trimmed) {
            return try await load(firstArgument: inner, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        let tl = trimmed.lowercased()
        if tl.hasPrefix("fsclientlauncher:") {
            return try await loadFromLauncherURIString(
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

    private static func parseLauncherLaunchURI(_ firstArgument: String) throws -> LaunchParameters {
        var withoutScheme = firstArgument.dropFirst("fsclientlauncher:".count)
        if withoutScheme.hasPrefix("//") {
            withoutScheme = withoutScheme.dropFirst(2)
        }
        guard let qIndex = withoutScheme.firstIndex(of: "?") else {
            throw LaunchError.invalidLauncherLaunchURI
        }
        let pathPart = withoutScheme[..<qIndex]
        guard pathPart.lowercased() == "launch" else {
            throw LaunchError.invalidLauncherLaunchURI
        }
        let query = String(withoutScheme[withoutScheme.index(after: qIndex)...])
        let items = URLComponents(string: "dummy://h?" + query)?.queryItems ?? []
        var dict: [String: String] = [:]
        for item in items {
            dict[item.name] = item.value ?? ""
        }
        return try LaunchParameters(args: dict)
    }

    private static func jsonDataForPersistence(from parameters: LaunchParameters) throws -> Data {
        let obj = parameters.args as [String: Any]
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: - Remote (http/https)

    /// Schreibt heruntergeladene **.fsclient**-JSON in eine temporäre Datei (wie Doppelklick auf eine lokale Definition).
    private static func writeLauncherDefinitionJsonToTemporaryFile(_ data: Data) throws -> URL {
        let name = "fsclient-remote-\(UUID().uuidString).fsclient"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Baut aus einer **http(s)-Definitions-URL** mit **jnlp** im Pfad dieselbe URL mit `…/api/fsclient…` (ohne lokale `.jnlp`-Datei oder XML).
    private static func rewriteRemoteJnlpDefinitionURLToClientAPI(_ url: URL) -> URL {
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

    private enum LauncherDefinitionDownloadResult {
        case jsonData(Data)
        /// Exakte `Location`-Zeile (meist `fsclientlauncher:launch?…`), nach Normalisierung von `fsclientlauncher://`.
        case redirectToLauncherScheme(location: String)
    }

    /// Lädt Rohbytes (JSON) oder erkennt **302 → fsclientlauncher:** (Server startet den Launcher so).
    private static func downloadLauncherDefinition(from url: URL) async throws -> LauncherDefinitionDownloadResult {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.default
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let delegate = LauncherDefinitionSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            LaunchLoadTrace.log(
                "downloadLauncherDefinition: Netzwerkfehler \(String(describing: type(of: error))) — \(error.localizedDescription) url=\(LaunchLoadTrace.preview(url.absoluteString))"
            )
            throw mapLauncherDefinitionTransportError(url: url, error: error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw LaunchError.clientDefinitionRemoteHTTP(-1)
        }
        if (200 ... 299).contains(http.statusCode) {
            return .jsonData(data)
        }
        if (300 ... 399).contains(http.statusCode) {
            if let raw = http.value(forHTTPHeaderField: "Location")?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let locNorm = normalizeLauncherRedirectLocation(raw)
                LaunchLoadTrace.log(
                    "downloadLauncherDefinition: HTTP \(http.statusCode) für \(LaunchLoadTrace.preview(url.absoluteString)) — Location=\(LaunchLoadTrace.preview(locNorm))"
                )
                let locLow = locNorm.lowercased()
                if locLow.hasPrefix("fsclientlauncher:") {
                    return .redirectToLauncherScheme(location: locNorm)
                }
            } else {
                LaunchLoadTrace.log(
                    "downloadLauncherDefinition: HTTP \(http.statusCode) ohne Location für \(LaunchLoadTrace.preview(url.absoluteString))"
                )
            }
            throw LaunchError.clientDefinitionRemoteHTTP(http.statusCode)
        }
        LaunchLoadTrace.log("downloadLauncherDefinition: HTTP \(http.statusCode) für \(LaunchLoadTrace.preview(url.absoluteString))")
        throw LaunchError.clientDefinitionRemoteHTTP(http.statusCode)
    }

    /// `fsclientlauncher://launch?…` aus Location-Header in die Form bringen, die `parseLauncherLaunchURI` erwartet.
    private static func normalizeLauncherRedirectLocation(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("fsclientlauncher://"),
           let r = s.range(of: "fsclientlauncher://", options: .caseInsensitive) {
            s = "fsclientlauncher:" + String(s[r.upperBound...])
        }
        return s
    }

    /// Direktes `fsclientlauncher:…` oder per **HTTP-302-Location** (gleiche Parser wie CLI/Tray).
    private static func loadFromLauncherURIString(
        _ trimmed: String,
        originalArgument: String,
        persistShortcutAfterLaunch: Bool
    ) async throws -> ParsedLaunchInput {
        let t0 = normalizeLauncherRedirectLocation(trimmed.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let r = t0.range(of: "fsclientlauncher:", options: .caseInsensitive) else {
            throw LaunchError.invalidLauncherLaunchURI
        }
        let t = "fsclientlauncher:" + String(t0[r.upperBound...])
        if let inner = embeddedHttpURLFromLauncherJnlpBridge(t) {
            return try await load(firstArgument: inner, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
        }
        var rest = String(t.dropFirst("fsclientlauncher:".count))
        if rest.hasPrefix("//") {
            rest = String(rest.dropFirst(2))
        }
        if let qIdx = rest.firstIndex(of: "?") {
            let pathPart = String(rest[..<qIdx]).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            if pathPart == "jnlp" {
                throw LaunchError.invalidLauncherLaunchURI
            }
        }
        let parameters = try parseLauncherLaunchURI(t)
        let data = try jsonDataForPersistence(from: parameters)
        return ParsedLaunchInput(
            parameters: parameters,
            jsonData: data,
            openedFromDirectLocalFile: false,
            localFilePath: nil,
            originalArgument: originalArgument,
            persistShortcutAfterLaunch: persistShortcutAfterLaunch
        )
    }

    private static func mapLauncherDefinitionTransportError(url: URL, error: Error) -> LaunchError {
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

    // MARK: - Broker-Stamm für registrierte Anwendungen (Icon.png)

    /// Liefert die normalisierte Broker-Basis-URL (`http(s)://…/Anwendung/`) für `Icon.png`, sofern aus Kürzel ableitbar.
    static func brokerBaseStringForApplicationIcon(shortcutTarget raw: String, backingFilePath: String?) -> String? {
        let ws = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = stripLeadingGarbageBeforeHTTPScheme(ws)
        if let embeddedTop = embeddedHttpURLFromLauncherJnlpBridge(trimmed) {
            return brokerBaseStringForApplicationIcon(shortcutTarget: embeddedTop, backingFilePath: nil)
        }
        let t0 = normalizeLauncherRedirectLocation(trimmed)
        if let r = t0.range(of: "fsclientlauncher:", options: .caseInsensitive) {
            let t = "fsclientlauncher:" + String(t0[r.upperBound...])
            if let inner = embeddedHttpURLFromLauncherJnlpBridge(t) {
                return brokerBaseStringForApplicationIcon(shortcutTarget: inner, backingFilePath: nil)
            }
            var rest = String(t.dropFirst("fsclientlauncher:".count))
            if rest.hasPrefix("//") {
                rest = String(rest.dropFirst(2))
            }
            if let qIdx = rest.firstIndex(of: "?") {
                let pathPart = String(rest[..<qIdx]).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                if pathPart == "jnlp" { return nil }
            }
            guard let params = try? parseLauncherLaunchURI(t) else { return nil }
            let b = params.broker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty else { return nil }
            return try? BrokerFetcher.normalizedBrokerURL(b).absoluteString
        }
        let tl = trimmed.lowercased()
        if tl.hasPrefix("http://") || tl.hasPrefix("https://") {
            let u = resolveHttpURLFromUserString(trimmed) ?? httpRemoteAPIURL(from: trimmed) ?? parseLenientHTTPURL(trimmed)
            guard let url = u else { return nil }
            return try? BrokerFetcher.normalizedBrokerURL(url.absoluteString).absoluteString
        }
        var paths: [String] = []
        if let b = backingFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            paths.append((b as NSString).standardizingPath)
        }
        let norm = RegisteredApplicationsStore.normalizeShortcutTarget(raw)
        if !norm.lowercased().hasPrefix("http://"), !norm.lowercased().hasPrefix("https://") {
            paths.append((norm as NSString).standardizingPath)
        }
        for p in paths {
            guard p.lowercased().hasSuffix(".fsclient"), FileManager.default.isReadableFile(atPath: p) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p, isDirectory: false)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let broker = obj[LaunchParameterKey.broker] as? String
            else { continue }
            let b = broker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty else { continue }
            if let s = try? BrokerFetcher.normalizedBrokerURL(b).absoluteString { return s }
        }
        return nil
    }

    // MARK: - Lokale Datei

    private static func resolveLocalFileURL(from trimmed: String) -> URL {
        if trimmed.hasPrefix("file:"), let u = URL(string: trimmed) {
            return u
        }
        return URL(fileURLWithPath: trimmed, isDirectory: false)
    }

    // MARK: - JSON

    private static func decodeLaunchParameters(from data: Data) throws -> LaunchParameters {
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let dict = obj.compactMapValues { $0 as? String }
            return try LaunchParameters(args: dict)
        } catch let e as LaunchError {
            throw e
        } catch {
            throw LaunchError.invalidJSONFile(error)
        }
    }
}

private final class LauncherDefinitionSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        HTTPOutboundRedirectPolicy.respondToRedirect(
            context: "downloadLauncherDefinition",
            response: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }
}
