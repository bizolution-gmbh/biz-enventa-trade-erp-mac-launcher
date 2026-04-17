import Foundation

// MARK: - Remote-Definitions-URLs (Tray / Kürzel / Startargumente)

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
