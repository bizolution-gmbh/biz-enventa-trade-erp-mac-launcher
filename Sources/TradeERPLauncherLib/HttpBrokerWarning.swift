import Foundation

/// Klartext-`http`-Broker liefern JAR-Listen, SHA-1-Hashes und JVM-Argumente unsigniert; ein
/// Angreifer im selben Netz kann Inhalte ersetzen — kombiniert mit weiteren Schutzschichten
/// (`stripCommandLineHijackingArguments`, SHA-1-Format-Validierung) ist das beherrschbar, aber
/// die Nutzer:in soll bewusst zustimmen.
///
/// Reine Logik ohne UI/Storage-Abhängigkeit — wir entscheiden hier nur, **ob** und für **welchen
/// Host** gefragt werden muss. Die UI ruft das bei jedem Start eines Klartext-`http`-Brokers auf.
enum HttpBrokerWarning {
    /// Was die UI als Reaktion auf einen Broker-Aufruf tun soll.
    enum Decision: Equatable {
        /// Kein `http://`-Broker (oder URL nicht parsebar) — keine Warnung nötig.
        case noWarningNeeded
        /// Host bereits in `acknowledgedHosts` — keine Warnung mehr nötig.
        case alreadyAcknowledged(host: String)
        /// UI soll Warnung anzeigen; nach `Fortfahren` den Host als „akzeptiert“ persistieren.
        case warn(host: String)
    }

    static func decide(brokerString: String, acknowledgedHosts: Set<String>) -> Decision {
        let trimmed = brokerString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return .noWarningNeeded }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" else {
            return .noWarningNeeded
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .noWarningNeeded
        }
        if acknowledgedHosts.contains(host) {
            return .alreadyAcknowledged(host: host)
        }
        return .warn(host: host)
    }
}
