import AppKit

/// Zeigt Stdout/Stderr des gestarteten `java`-Prozesses, wenn in den Einstellungen die Konsole gewünscht ist.
/// Ergänzt die Java-Client-Flags (`DisplayConsole`, `-DDisplayConsole`), falls der Client keine eigene Konsole öffnet.
final class JavaProcessOutputWindow: NSObject, NSWindowDelegate {
    static let shared = JavaProcessOutputWindow()

    private var window: NSWindow?
    private var textView: NSTextView?

    func present() {
        if Thread.isMainThread {
            presentOnMain()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.presentOnMain()
            }
        }
    }

    private func presentOnMain() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 880, height: 480)
        let rect = NSRect(origin: .zero, size: size)
        let w = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Java-Ausgabe (Stdout/Stderr)"
        let scroll = NSScrollView(frame: rect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.autoresizingMask = [.width, .height]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        w.contentView = scroll
        w.delegate = self
        w.center()
        window = w
        textView = tv
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func append(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let tv = self.textView else { return }
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.textColor,
                ]
            )
            tv.textStorage?.append(attr)
            let len = (tv.string as NSString).length
            tv.scrollRangeToVisible(NSRange(location: max(0, len - 1), length: 1))
        }
    }

    /// Synchron auf dem Hauptthread, damit vor einem `throw` noch die Abschlusszeile erscheint.
    func appendFooter(exitCode: Int32) {
        let block = { [weak self] in
            guard let self else { return }
            self.appendOnMain(
                "\n—— Java-Prozess beendet (Exit-Code \(exitCode)). Das Ausgabefenster kann geschlossen werden; der Launcher bleibt aktiv (Menüleisten-Symbol). ——\n"
            )
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }

    private func appendOnMain(_ text: String) {
        guard let tv = textView else { return }
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ]
        )
        tv.textStorage?.append(attr)
        let len = (tv.string as NSString).length
        tv.scrollRangeToVisible(NSRange(location: max(0, len - 1), length: 1))
    }

    func windowWillClose(_ notification: Notification) {
        // Nur Fenster freigeben: App und ggf. laufender Java-Kindprozess bleiben aktiv (Tray / Dock).
        window = nil
        textView = nil
    }
}
