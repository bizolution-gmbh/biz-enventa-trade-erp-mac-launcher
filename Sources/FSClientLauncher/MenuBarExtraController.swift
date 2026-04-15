import AppKit

/// Menüleisten-Symbol (rechts oben) mit Zugriff auf Einstellungen und gespeicherte `.fsclient`-Dateien.
@MainActor
final class MenuBarExtraController: NSObject {
    static let shared = MenuBarExtraController()

    private var statusItem: NSStatusItem?
    private var shortcutsObserver: NSObjectProtocol?

    var hasStatusItem: Bool { statusItem != nil }

    private override init() {
        super.init()
    }

    /// Wird beim ersten App-Start aufgerufen; idempotent. Symbol sofort sichtbar (nicht erst nach .fsclient).
    func installIfNeeded() {
        if shortcutsObserver == nil {
            shortcutsObserver = NotificationCenter.default.addObserver(
                forName: .fsclShortcutsChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.rebuildMenu() }
            }
        }
        guard statusItem == nil else {
            rebuildMenu()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // Menüleiste: exakt `enventa-mark-cropped.svg` als Template (WebKit-Snapshot), asynchron.
            button.toolTip = "FS Client Launcher"
            button.appearsDisabled = false
            let mark = TrayMarkTemplateRenderer.menuBarImage(side: 18)
            mark.size = NSSize(width: 18, height: 18)
            button.image = mark
        } else {
            fputs("FSClientLauncher: NSStatusItem ohne Button — Menüleisten-Icon nicht darstellbar.\n", stderr)
        }
        if #available(macOS 11.0, *) {
            item.isVisible = true
        }
        statusItem = item
        rebuildMenu()
    }

    func remove() {
        if let s = statusItem {
            NSStatusBar.system.removeStatusItem(s)
        }
        statusItem = nil
    }

    func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Einstellungen …",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let header = NSMenuItem(title: "FS-Client-Dateien", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let store = FsClientShortcutsStore.shared
        for rec in store.file.shortcuts {
            let mi = NSMenuItem(title: rec.displayName, action: #selector(openFsClient(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = rec.path as NSString
            menu.addItem(mi)
        }

        if store.file.shortcuts.isEmpty {
            let empty = NSMenuItem(title: "Keine Einträge", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "FS Client Launcher beenden",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openSettings(_ sender: Any?) {
        AppDelegate.shared?.showConfigWindowFromMenuBar()
    }

    @objc private func openFsClient(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let path = item.representedObject as? String
        else { return }
        AppDelegate.shared?.launchFsClientFromMenuBar(path: path)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
