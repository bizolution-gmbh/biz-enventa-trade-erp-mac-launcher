import Foundation

enum LaunchError: Error, LocalizedError {
    case missingBroker
    case noArguments
    case invalidURI(String)
    case invalidFsClientLauncherURI
    case invalidJSONFile(Error)
    case brokerHTTP(Int)
    case brokerDownload(Error)
    case jarShaMismatch(String)
    case jarDownload(String, Error)
    case noJavaVersion
    case javaHomeMissing(String)
    case noMainJar
    case clientExit(Int32)
    var errorDescription: String? {
        switch self {
        case .missingBroker: "Im Startparameter fehlt der Schlüssel „broker“."
        case .noArguments: "Kein Startargument (Broker-URL oder Konfigurationsdatei)."
        case .invalidURI(let s): "Ungültige URI: \(s)"
        case .invalidFsClientLauncherURI:
            "Erwartet z. B. fsclientlauncher:launch?broker=https%3A%2F%2F… oder eine JSON-Datei wie unter Windows."
        case .invalidJSONFile(let e): "JSON konnte nicht gelesen werden: \(e.localizedDescription)"
        case .brokerHTTP(let c): "Broker-Antwort HTTP \(c)"
        case .brokerDownload(let e): "Broker-Download fehlgeschlagen: \(e.localizedDescription)"
        case .jarShaMismatch(let href): "SHA-1 stimmt nicht: \(href)"
        case .jarDownload(let href, let e): "JAR-Download \(href): \(e.localizedDescription)"
        case .noJavaVersion: "Keine unterstützte Java-Version laut Broker und Konfiguration."
        case .javaHomeMissing(let msg): msg
        case .noMainJar: "Weder MainClass noch als „main“ markiertes JAR in den Broker-Daten."
        case .clientExit(let code): "Java-Prozess beendet mit Code \(code)."
        }
    }
}
