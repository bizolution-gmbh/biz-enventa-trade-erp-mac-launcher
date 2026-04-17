import Darwin
import Foundation

/// Diagnose: **stderr** (kurz, synchron) + `AppPaths.logFilesDirectory/launcher-load-trace.log` (asynchron).
/// Wichtig: kein `DispatchQueue.sync` + `FileManager` vom **MainThread** (z. B. Menü-Rebuild) — das kann mit Main-Queue-Rückrufen **deadlocken** und die App beenden lassen.
enum LaunchLoadTrace {
    private static let fileQueue = DispatchQueue(label: "de.frameworksystems.fscl.launchloadtrace.file", qos: .utility)

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

/// Typische Copy-Paste-Artefakte entfernen (Browser/Web, Mail), ohne `fsclientlauncher:` zu zerstören.
fileprivate func sanitizeHttpURLUserInput(_ raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // Copy-Paste aus manchen UIs: volle Breite „:“ / „/“ — bricht `URL(string:)` / Host-Erkennung
    t = t.replacingOccurrences(of: "\u{FF1A}", with: ":").replacingOccurrences(of: "\u{FF0F}", with: "/")
    if t.hasPrefix("<"), t.hasSuffix(">") {
        t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    t = t.replacingOccurrences(of: "\0", with: "")
    t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
    t = t.replacingOccurrences(of: "\u{FEFF}", with: "")
    t = t.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
    // Zeilenumbrüche / Steuerzeichen in der Mitte (Copy-Paste aus Mail/Excel) brechen URL(string:)
    t = t.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    t = t.replacingOccurrences(of: "\t", with: "")
    for u in [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{2028}", "\u{2029}",
        "\u{200E}", "\u{200F}", "\u{061C}", // Bidirektional / unsichtbare Steuerzeichen vor „http“
    ] {
        t = t.replacingOccurrences(of: u, with: "")
    }
    let tl = t.lowercased()
    if tl.hasPrefix("https:/"), !tl.hasPrefix("https://") {
        t = "https://" + String(t.dropFirst("https:/".count))
    } else if tl.hasPrefix("http:/"), !tl.hasPrefix("http://") {
        t = "http://" + String(t.dropFirst("http:/".count))
    }
    // Anführungszeichen am Rand (JSON, Excel, Mail) — ohne diese liefert URL(string:) oft nil
    let quoteEdges = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
    for _ in 0 ..< 4 {
        let before = t
        t = t.trimmingCharacters(in: quoteEdges)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == before { break }
    }
    // Markdown: (http://…)
    if t.hasPrefix("("), t.hasSuffix(")"), t.dropFirst().dropLast().contains("://") {
        t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return t
}

/// Entfernt Text vor dem ersten `https://` bzw. `http://` (Mail, Chat, „URL: …“). Zuerst **https**, damit nicht `http` innerhalb von `https` matched.
/// Bei `fsclientlauncher:…` keine Änderung (sonst würde ein Klartext-`https://` in der Query die Zeichenkette zerstückeln).
fileprivate func stripLeadingGarbageBeforeHTTPScheme(_ raw: String) -> String {
    var t = sanitizeHttpURLUserInput(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    let tl = t.lowercased()
    guard !tl.hasPrefix("fsclientlauncher:") else { return t }
    // Lokale Datei-URLs oder Pfade nie anhand eines eingebetteten „http://“ abschneiden
    guard !tl.hasPrefix("file:") else { return t }
    if tl.hasPrefix("http://") || tl.hasPrefix("https://") { return t }
    if let r = t.range(of: "https://", options: .caseInsensitive) {
        t = String(t[r.lowerBound...])
    } else if let r = t.range(of: "http://", options: .caseInsensitive) {
        t = String(t[r.lowerBound...])
    }
    return t
}

/// Wenn `URL(string:)` scheitert (z. B. unsichtbare Steuerzeichen direkt vor `http`), findet der System-Detector oft trotzdem die **http(s)**-URL.
fileprivate func extractHttpURLWithDataDetector(in raw: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let ns = raw as NSString
    let len = ns.length
    guard len > 0 else { return nil }
    var found: URL?
    detector.enumerateMatches(in: raw, options: [], range: NSRange(location: 0, length: len)) { match, _, stop in
        guard let match, let u = match.url,
              let sch = u.scheme?.lowercased(), sch == "http" || sch == "https",
              u.host != nil else { return }
        found = u
        stop.pointee = true
    }
    return found
}

/// Erkennt **http(s)**-Remote-URLs zuverlässiger als `URL(string:)` (Encoding, Komponenten).
/// Reihenfolge: zuerst **normales** `URL(string:)` (wie vom System geliefert), dann Fallbacks — kein nachträgliches Abschneiden von Zeichen am Ende (kann gültige Queries zerstören).
fileprivate func httpRemoteAPIURL(from raw: String) -> URL? {
    let t = stripLeadingGarbageBeforeHTTPScheme(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = t.lowercased()
    guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
        return extractHttpURLWithDataDetector(in: t) ?? extractHttpURLWithDataDetector(in: raw)
    }
    if let u = URL(string: t), let scheme = u.scheme?.lowercased(), (scheme == "http" || scheme == "https"), u.host != nil {
        return u
    }
    guard var c = URLComponents(string: t) else {
        return parseLenientHTTPURL(t) ?? extractHttpURLWithDataDetector(in: t) ?? extractHttpURLWithDataDetector(in: raw)
    }
    if c.scheme == nil, lower.hasPrefix("https://") {
        c.scheme = "https"
    } else if c.scheme == nil, lower.hasPrefix("http://") {
        c.scheme = "http"
    }
    guard let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https", c.host != nil else {
        return parseLenientHTTPURL(t) ?? extractHttpURLWithDataDetector(in: t) ?? extractHttpURLWithDataDetector(in: raw)
    }
    if let u = c.url { return u }
    let spaced = t.replacingOccurrences(of: " ", with: "%20")
    if let u = URL(string: spaced), u.host != nil { return u }
    if let qIdx = t.firstIndex(of: "?") {
        let head = String(t[..<qIdx])
        let query = String(t[t.index(after: qIdx)...])
        let allowed = CharacterSet.urlQueryAllowed
        if let qEnc = query.addingPercentEncoding(withAllowedCharacters: allowed), let u = URL(string: head + "?" + qEnc), u.host != nil {
            return u
        }
    }
    if let u = parseLenientHTTPURL(t) { return u }
    if #available(macOS 14.0, *) {
        if let u = URL(string: t, encodingInvalidCharacters: true),
           let scheme = u.scheme?.lowercased(), (scheme == "http" || scheme == "https"), u.host != nil {
            return u
        }
    }
    return extractHttpURLWithDataDetector(in: t) ?? extractHttpURLWithDataDetector(in: raw)
}

/// Eine Zeile → **eine** `http(s):`-`URL` (Tray, argv, Einfügen): strikt zuerst, dann Fallbacks (`URLComponents` oft erfolgreich, wenn `URL(string:)` nil liefert).
fileprivate func resolveHttpURLFromUserString(_ raw: String) -> URL? {
    let t = stripLeadingGarbageBeforeHTTPScheme(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    let l = t.lowercased()
    guard l.hasPrefix("http://") || l.hasPrefix("https://") else { return nil }
    if let u = URL(string: t),
       let sch = u.scheme?.lowercased(), sch == "http" || sch == "https",
       u.host != nil {
        return u
    }
    if #available(macOS 14.0, *) {
        if let u = URL(string: t, encodingInvalidCharacters: true),
           let sch = u.scheme?.lowercased(), sch == "http" || sch == "https",
           u.host != nil {
            return u
        }
    }
    if var c = URLComponents(string: t) {
        if c.scheme == nil, l.hasPrefix("https://") { c.scheme = "https" }
        else if c.scheme == nil, l.hasPrefix("http://") { c.scheme = "http" }
        if let sch = c.scheme?.lowercased(), sch == "http" || sch == "https", c.host != nil, let u = c.url, u.host != nil {
            return u
        }
    }
    if let dec = t.removingPercentEncoding, dec != t {
        let d = stripLeadingGarbageBeforeHTTPScheme(dec).trimmingCharacters(in: .whitespacesAndNewlines)
        let dl = d.lowercased()
        if dl.hasPrefix("http://") || dl.hasPrefix("https://") {
            if let u = URL(string: d),
               let sch = u.scheme?.lowercased(), sch == "http" || sch == "https",
               u.host != nil {
                return u
            }
            if var c2 = URLComponents(string: d) {
                if c2.scheme == nil, dl.hasPrefix("https://") { c2.scheme = "https" }
                else if c2.scheme == nil, dl.hasPrefix("http://") { c2.scheme = "http" }
                if let sch = c2.scheme?.lowercased(), sch == "http" || sch == "https", c2.host != nil, let u = c2.url, u.host != nil {
                    return u
                }
            }
        }
    }
    if let u = parseLenientHTTPURL(t) { return u }
    if let u = httpRemoteAPIURL(from: t) { return u }
    if let u = buildHttpURLFromAggressiveLineParsing(t) { return u }
    return extractHttpURLWithDataDetector(in: t)
}

/// Fallback, wenn `URL(string:)` / `URLComponents` scheitern: `scheme://authority/path?query` manuell zusammensetzen und Query ggf. kodieren.
fileprivate func parseLenientHTTPURL(_ raw: String) -> URL? {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let low = t.lowercased()
    guard low.hasPrefix("http://") || low.hasPrefix("https://") else { return nil }
    guard let rColonSlash = t.range(of: "://") else { return nil }
    let scheme = String(t[..<rColonSlash.lowerBound]).lowercased()
    guard scheme == "http" || scheme == "https" else { return nil }
    let afterSlashes = t[rColonSlash.upperBound...]
    guard !afterSlashes.isEmpty else { return nil }
    let authority: String
    let pathAndQuery: String
    if let slash = afterSlashes.firstIndex(of: "/") {
        authority = String(afterSlashes[..<slash])
        pathAndQuery = String(afterSlashes[slash...])
    } else {
        authority = String(afterSlashes)
        pathAndQuery = "/"
    }
    guard !authority.isEmpty else { return nil }
    let rebuilt: String
    if let qIdx = pathAndQuery.firstIndex(of: "?") {
        let pathPart = String(pathAndQuery[..<qIdx])
        let queryPart = String(pathAndQuery[pathAndQuery.index(after: qIdx)...])
        let allowed = CharacterSet.urlQueryAllowed
        let qEnc = queryPart.addingPercentEncoding(withAllowedCharacters: allowed) ?? queryPart
        rebuilt = "\(scheme)://\(authority)\(pathPart)?\(qEnc)"
    } else {
        rebuilt = "\(scheme)://\(authority)\(pathAndQuery)"
    }
    if let u = URL(string: rebuilt), u.host != nil { return u }
    if #available(macOS 14.0, *) {
        if let u = URL(string: rebuilt, encodingInvalidCharacters: true), u.host != nil { return u }
    }
    return nil
}

/// Letzter Versuch: einfache **http(s)://Host/Pfad?Query**-Zeile (Regex), z. B. wenn `URL(string:)` am Original scheitert.
fileprivate func buildHttpURLFromAggressiveLineParsing(_ raw: String) -> URL? {
    let t = raw.replacingOccurrences(of: "\\", with: "/")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let low = t.lowercased()
    guard low.hasPrefix("http://") || low.hasPrefix("https://") else { return nil }
    let pattern = #"^(https?://[^\s]+)$"#
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let m = re.firstMatch(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length)),
          let r = Range(m.range(at: 1), in: t) else { return nil }
    let line = String(t[r])
    if let u = URL(string: line), u.host != nil { return u }
    if #available(macOS 14.0, *) {
        if let u = URL(string: line, encodingInvalidCharacters: true), u.host != nil { return u }
    }
    return parseLenientHTTPURL(line)
}

/// Web-API zur **`.fsclient`-JSON-Definition** im Muster `http(s)://<Server>/<Anwendung>/api/fsclient?…` (Schritt 1).
func remoteFsClientDefinitionApiURL(from raw: String) -> URL? {
    guard let u = resolveHttpURLFromUserString(raw) else { return nil }
    let pathDecoded = (u.path.removingPercentEncoding ?? u.path).lowercased()
    let abs = u.absoluteString.lowercased()
    guard pathDecoded.contains("/api/fsclient") || abs.contains("/api/fsclient") else { return nil }
    return u
}

/// Erkennt `http(s)://…/…fsclient…`-URLs (JSON-API), ggf. abweichend von `…/api/fsclient…`.
func fsclientRemoteAPIURL(from raw: String) -> URL? {
    if let u = remoteFsClientDefinitionApiURL(from: raw) { return u }
    guard let u = resolveHttpURLFromUserString(raw) else { return nil }
    let lower = stripLeadingGarbageBeforeHTTPScheme(raw).lowercased()
    let blob = (u.path + "?" + (u.query ?? "")).lowercased() + u.absoluteString.lowercased() + lower
    guard blob.contains("fsclient") else { return nil }
    return u
}

/// Erkennt **http(s)**-Definitions-URLs mit **jnlp** im Pfad (typisch `…/api/jnlp?…`) — für Kürzel-Validierung und Umschreiben auf `…/api/fsclient…` vor dem Download.
func jnlpRemoteAPIURL(from raw: String) -> URL? {
    let cleaned = stripLeadingGarbageBeforeHTTPScheme(raw)
    guard let u = resolveHttpURLFromUserString(cleaned) ?? httpRemoteAPIURL(from: cleaned) else { return nil }
    let path = u.path.lowercased()
    let abs = u.absoluteString.lowercased()
    if path.contains("/api/jnlp") { return u }
    if path.hasSuffix("/jnlp") { return u }
    let last = (path as NSString).lastPathComponent
    if last == "jnlp" || last.hasPrefix("jnlp.") { return u }
    if abs.range(of: #"[/]api[/._-]?jnlp"#, options: .regularExpression) != nil { return u }
    if abs.range(of: #"[/]jnlp\?"#, options: .regularExpression) != nil { return u }
    let segs = path.split(separator: "/").map { String($0).lowercased() }
    if segs.contains(where: { $0 == "jnlp" || $0.hasPrefix("jnlp.") }) { return u }
    let cl = cleaned.lowercased()
    if cl.contains("/api/jnlp") || cl.contains("api/jnlp?") || cl.contains("api/jnlp&") { return u }
    return nil
}

/// Ergebnis von `LaunchConfiguration.load`: Client-Konfiguration plus Roh-JSON für Import ins App-Support-Verzeichnis.
struct ParsedFsClientLaunch: Sendable {
    let client: ApiFsClient
    /// Rohbytes der .fsclient-JSON (lokal gelesen oder per HTTP geladen).
    let jsonData: Data
    /// `true`, wenn die Konfiguration aus einer **lokalen Datei** kam (Finder, `openFile`, oder temporäre `.fsclient` nach Download von einer **http(s)-Definition-URL**).
    let openedFromDirectLocalFile: Bool
    /// Standardisierter lokaler Pfad, falls `openedFromDirectLocalFile`.
    let localFilePath: String?
    /// Ursprüngliches Startargument (Pfad, `file:`, `http(s):`, `fsclientlauncher:`).
    let originalArgument: String
    /// `false`, wenn der Start **intern** aus dem Tray mit gespeicherter `fsclientlauncher:`-URL kommt — dann kein `upsertAfterSuccessfulLaunch`.
    let persistShortcutAfterLaunch: Bool
}

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

/// Nur **http/https**-Weiterleitungen zulassen — sonst bricht `URLSession` oft mit **NSURLError -1002** ab („URL nicht unterstützt“).
private final class FsClientDefinitionSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let next = request.url else {
            LaunchLoadTrace.log("downloadFsClientDefinition: Redirect ohne Ziel-URL (HTTP \(response.statusCode))")
            completionHandler(nil)
            return
        }
        let sch = next.scheme?.lowercased() ?? ""
        if sch == "fsclientlauncher" {
            LaunchLoadTrace.log(
                "downloadFsClientDefinition: HTTP \(response.statusCode) Weiterleitung auf fsclientlauncher (kein HTTP-Follow; Ziel steht in der 302-Location): \(LaunchLoadTrace.preview(next.absoluteString))"
            )
            completionHandler(nil)
            return
        }
        guard sch == "http" || sch == "https" else {
            LaunchLoadTrace.log(
                "downloadFsClientDefinition: HTTP \(response.statusCode) Weiterleitung abgelehnt — Schema „\(sch)“: \(LaunchLoadTrace.preview(next.absoluteString))"
            )
            completionHandler(nil)
            return
        }
        guard let host = next.host, !host.isEmpty else {
            LaunchLoadTrace.log("downloadFsClientDefinition: Redirect abgelehnt (ohne Host) HTTP \(response.statusCode)")
            completionHandler(nil)
            return
        }
        LaunchLoadTrace.log(
            "downloadFsClientDefinition: folge HTTP-Redirect \(response.statusCode) → \(LaunchLoadTrace.preview(next.absoluteString))"
        )
        completionHandler(request)
    }
}
