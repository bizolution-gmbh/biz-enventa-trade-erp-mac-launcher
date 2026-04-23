import Foundation

enum LaunchError: Error, LocalizedError {
    case missingBroker
    case noArguments
    case invalidURI(String)
    /// Broker-Basis aus der **.fsclient**-JSON ließ sich nicht in eine gültige **http(s)**-URL überführen.
    case invalidBrokerURI(String)
    case invalidLauncherLaunchURI
    case invalidJSONFile(Error)
    case brokerHTTP(Int)
    case brokerDownload(Error)
    case jarShaMismatch(String)
    case jarDownload(String, Error)
    case noJavaVersion
    case javaHomeMissing(String)
    case noMainJar
    case clientExit(Int32)
    /// Download einer per **http(s)** übergebenen `.fsclient`-Definition.
    case clientDefinitionRemoteHTTP(Int)
    /// Netzwerk-/URLSession-Fehler beim Abruf der Definitions-URL (nicht der HTTP-Status vom Server).
    case fsclientDefinitionDownloadFailed(url: String, reason: String)
    /// Broker-JAR oder Splash verweist auf kein http(s) (z. B. `file:`) — wird aus Sicherheitsgründen abgelehnt.
    case disallowedOutboundURL(String)
    /// Download oder Entpacken der Java-8-Laufzeit (Azul Zulu + JavaFX) in den Launcher-Ordner (Erststart-Assistent).
    case jre8RuntimeDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBroker: "Im Startparameter fehlt der Schlüssel „broker“."
        case .noArguments: "Kein Startargument (Broker-URL oder Konfigurationsdatei)."
        case .invalidURI(let s):
            if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") {
                "URL nicht unterstützt: \(s)\n\nUnterstützt werden https/http-URLs mit …/api/fsclient… oder …/api/jnlp… (wird intern auf …/api/fsclient… umgeschrieben), lokale .fsclient-Dateien sowie die Brücken-URL „fsclientlauncher:jnlp?url=“ + kodierte http(s)-Definitions-Adresse (Lesezeichen, falls der Browser die URL nicht an Apps übergibt)."
            } else {
                "Ungültige URI: \(s)"
            }
        case .invalidBrokerURI(let s):
            "Broker-Adresse nicht unterstützt oder unlesbar: \(s)\n\nErwartet wird ein http(s)-Broker-Stamm wie „http://server/Anwendungsname“ (Feld „broker“ in der vom Server gelieferten Konfiguration)."
        case .invalidLauncherLaunchURI:
            "Erwartet z. B. fsclientlauncher:launch?broker=https%3A%2F%2F… oder fsclientlauncher:jnlp?url=https%3A%2F%2F…%2Fapi%2Fjnlp%3F… (Brücke zur http(s)-Adresse) bzw. eine lokale .fsclient-JSON-Datei wie unter Windows."
        case .invalidJSONFile(let e): "JSON konnte nicht gelesen werden: \(e.localizedDescription)"
        case .brokerHTTP(let c): "Broker-Antwort HTTP \(c)"
        case .brokerDownload(let e):
            "Broker-Download fehlgeschlagen: \(networkFailureSummary(for: e))\(URLError.launcherConnectivityHint(for: e).map { "\n\n\($0)" } ?? "")"
        case .jarShaMismatch(let href): "SHA-1 stimmt nicht: \(href)"
        case .jarDownload(let href, let e):
            "JAR-Download \(href): \(networkFailureSummary(for: e))\(URLError.launcherConnectivityHint(for: e).map { "\n\n\($0)" } ?? "")"
        case .noJavaVersion: "Keine unterstützte Java-Version laut Broker und Konfiguration."
        case .javaHomeMissing(let msg): msg
        case .noMainJar: "Weder MainClass noch als „main“ markiertes JAR in den Broker-Daten."
        case .clientExit(let code): "Java-Prozess beendet mit Code \(code)."
        case .clientDefinitionRemoteHTTP(let c):
            if (300 ... 399).contains(c) {
                "Download der .fsclient-Datei: HTTP \(c) (Weiterleitung). Es kam keine JSON-Definition an — Anmeldung am Server, Proxy oder ungültige „Location“-Weiterleitung prüfen."
            } else {
                "Download der .fsclient-Datei: HTTP \(c)."
            }
        case .fsclientDefinitionDownloadFailed(let url, let reason):
            """
            Die Konfiguration konnte von der Server-URL nicht geladen werden.

            \(reason)

            URL:
            \(url)
            """
        case .disallowedOutboundURL(let hint):
            "Download abgelehnt: Es sind nur http(s)-URLs mit Host erlaubt (Broker-Daten). Verworfen: \(hint)"
        case .jre8RuntimeDownloadFailed(let msg):
            "Java-8-Laufzeit (Zulu/JavaFX): \(msg)"
        }
    }
}

/// Kurzfassung für UI; bei **-1009** nicht allein Apples oft irreführende „keine Internetverbindung“-Formulierung verwenden.
private func networkFailureSummary(for error: Error) -> String {
    if let u = error.underlyingURLErrorForLauncher, u.code == .notConnectedToInternet {
        return "Netzwerkfehler \(u.code.rawValue) (macOS/URLSession meldet das häufig pauschal als fehlende Internetverbindung — das ist technisch nicht gleichbedeutend mit „Broker nicht erreichbar“ oder „WLAN aus“)."
    }
    return error.localizedDescription
}

private extension Error {
    /// `URLSession` liefert mitunter `NSError` mit eingebettetem `URLError`.
    var underlyingURLErrorForLauncher: URLError? {
        if let u = self as? URLError { return u }
        var current: Error = self
        for _ in 0 ..< 4 {
            let ns = current as NSError
            guard let next = ns.userInfo[NSUnderlyingErrorKey] as? Error else { break }
            if let u = next as? URLError { return u }
            current = next
        }
        return nil
    }
}

extension URLError {
    /// Ergänzung zu `localizedDescription` (z. B. irreführendes „kein Internet“ bei Code -1009).
    static func launcherConnectivityHint(for error: Error) -> String? {
        guard let u = error.underlyingURLErrorForLauncher else { return nil }
        switch u.code {
        case .notConnectedToInternet:
            return """
            Hinweis: Der Code \(u.code.rawValue) wird von Apple für mehrere Fälle genutzt, in denen URLSession **keinen brauchbaren Netzwerkweg** für die Anfrage findet — nicht nur bei tatsächlich fehlendem Internet. Dazu zählen u. a. Proxy/VPN, Captive Portals, kurz nach dem Aufwachen des Systems oder andere lokale Netzwerkrichtlinien. Die Meldung belegt damit **nicht**, dass der Broker-Host grundsätzlich unerreichbar wäre.

            Wenn macOS zuvor nach **„Lokalem Netzwerk“** (interne Firmen-Server) gefragt hat und die Freigabe **abgelehnt** wurde: unter **Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk** den Eintrag **enventa Trade ERP Launcher** aktivieren — sonst blockiert das System TCP zu vielen internen Adressen (der Browser kann davon unabhängig weiter funktionieren).
            """
        case .cannotConnectToHost, .timedOut, .networkConnectionLost:
            return """
            Hinweis: Zielrechner/Port nicht erreichbar oder Zeitüberschreitung (Code \(u.code.rawValue)). Prüfen Sie Broker-URL, VPN, Proxy und ob der Anwendungsserver von diesem Mac aus erreichbar ist.
            """
        case .cannotFindHost, .dnsLookupFailed:
            return "Hinweis: DNS/Hostname (Code \(u.code.rawValue)) — VPN oder Firmen-DNS nötig?"
        case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected:
            return "Hinweis: TLS/Zertifikat (Code \(u.code.rawValue)) — HTTPS-Zwischenzertifikate oder Firmen-Proxy prüfen."
        default:
            return nil
        }
    }
}
