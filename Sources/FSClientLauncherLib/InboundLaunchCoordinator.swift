import AppKit
import Foundation

/// Dedupe und `LaunchConfiguration.load` für **URL**- und **String**-Starts — entlastet `AppDelegate`.
@MainActor
final class InboundLaunchCoordinator {
    unowned let host: AppDelegate
    private var inFlightLaunchKeys: Set<String> = []

    init(host: AppDelegate) {
        self.host = host
    }

    func runLaunchArgument(_ url: URL, persistShortcutAfterLaunch: Bool = true) async {
        let dedupeKey = url.absoluteString.lowercased()
        if inFlightLaunchKeys.contains(dedupeKey) {
            LaunchLoadTrace.log("runLaunchArgument(URL): Dedupe — Start übersprungen, key=\(LaunchLoadTrace.preview(dedupeKey, max: 220))")
            return
        }
        inFlightLaunchKeys.insert(dedupeKey)
        defer { inFlightLaunchKeys.remove(dedupeKey) }
        do {
            let parsed = try await LaunchConfiguration.load(systemOpenURL: url, persistShortcutAfterLaunch: persistShortcutAfterLaunch)
            try await host.runLaunchCoordinator(parsed: parsed)
        } catch is CancellationError {
            await MainActor.run { host.ensureTrayAfterLaunchFailure() }
        } catch {
            LaunchLoadTrace.log("runLaunchArgument(URL): Fehler \(String(describing: type(of: error))) — \(error.localizedDescription)")
            await MainActor.run {
                host.presentLaunchError(error)
            }
        }
    }

    func runLaunchArgument(_ raw: String, persistShortcutAfterLaunch: Bool = true) async {
        let dedupeKey = FsClientShortcutsStore.normalizeShortcutTarget(raw).lowercased()
        if inFlightLaunchKeys.contains(dedupeKey) {
            LaunchLoadTrace.log("runLaunchArgument(String): Dedupe — Start übersprungen, key=\(LaunchLoadTrace.preview(dedupeKey, max: 220))")
            return
        }
        inFlightLaunchKeys.insert(dedupeKey)
        defer { inFlightLaunchKeys.remove(dedupeKey) }
        do {
            let parsed = try await LaunchConfiguration.load(
                firstArgument: raw,
                persistShortcutAfterLaunch: persistShortcutAfterLaunch
            )
            try await host.runLaunchCoordinator(parsed: parsed)
        } catch is CancellationError {
            await MainActor.run { host.ensureTrayAfterLaunchFailure() }
        } catch {
            LaunchLoadTrace.log("runLaunchArgument(String): Fehler \(String(describing: type(of: error))) — \(error.localizedDescription)")
            await MainActor.run {
                host.presentLaunchError(error)
            }
        }
    }
}
