import Foundation

/// Persistente Liste der **vom Nutzer bestätigten** `http://`-Broker-Hosts (UserDefaults).
/// Wird von der UI-Schicht (NSAlert in `AppDelegate`) zusammen mit `HttpBrokerWarning.decide`
/// genutzt — die reine Entscheidungslogik bleibt testbar und kennt UserDefaults nicht.
enum HttpBrokerAcknowledgedHostsStore {
    static let userDefaultsKey = "TradeERPLauncherAcknowledgedHttpBrokerHosts"

    static func loadAcknowledgedHosts(from defaults: UserDefaults = .standard) -> Set<String> {
        let raw = defaults.array(forKey: userDefaultsKey) as? [String] ?? []
        return Set(raw.map { $0.lowercased() }.filter { !$0.isEmpty })
    }

    static func acknowledge(host: String, in defaults: UserDefaults = .standard) {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        var current = loadAcknowledgedHosts(from: defaults)
        guard !current.contains(normalized) else { return }
        current.insert(normalized)
        defaults.set(Array(current).sorted(), forKey: userDefaultsKey)
    }
}
