import Foundation

// MARK: - HTTP-Eingabe normalisieren und in URL auflösen
// Wird von `LaunchConfiguration` und `LaunchRemoteDefinitionURLs` genutzt.

/// Typische Copy-Paste-Artefakte entfernen (Browser/Web, Mail), ohne `fsclientlauncher:` zu zerstören.
func sanitizeHttpURLUserInput(_ raw: String) -> String {
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
func stripLeadingGarbageBeforeHTTPScheme(_ raw: String) -> String {
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
func extractHttpURLWithDataDetector(in raw: String) -> URL? {
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
func httpRemoteAPIURL(from raw: String) -> URL? {
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
func resolveHttpURLFromUserString(_ raw: String) -> URL? {
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
        if let sch = c.scheme?.lowercased(), sch == "http" || sch == "https", c.host != nil, let u = c.url {
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
                if let sch = c2.scheme?.lowercased(), sch == "http" || sch == "https", c2.host != nil, let u = c2.url {
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
func parseLenientHTTPURL(_ raw: String) -> URL? {
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
func buildHttpURLFromAggressiveLineParsing(_ raw: String) -> URL? {
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
