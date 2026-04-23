import Foundation

/// Sichtbarer **Produktname** des Launchers (enventa Trade ERP) und Ablage unter `~/Library/.../bizolution/`.
/// Die **BIZOLUTION GmbH** stellt diesen Launcher als Vertriebs- und Technologiepartner bereit; die **Logos** in der App sind die **Bizolution**-Marken, nicht die Hersteller-Logos des ERP (Java-Client weiter mit dessen eigenen Icons).
enum LauncherProductNaming {
    /// Menüleiste, Fenstertitel, `CFBundleDisplayName`, Build-Skript `.app`-Name (ohne `.app`-Suffix hier).
    static let displayName = "enventa Trade ERP Launcher"

    /// Ordnername unter `Library/Application Support/bizolution/` und `Library/Caches/bizolution/`.
    static let appDataFolderLeafName = displayName

    /// Für `‑Dapple.awt.application.name` (Java-Client / ERP-Anwendung in der Menüleiste).
    static let javaAwtApplicationMenuBarName = "enventa Trade ERP"
}
