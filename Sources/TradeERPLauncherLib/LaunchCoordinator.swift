import AppKit
import Foundation

/// Hält laufende **java**-`Process`-Objekte und zugehörige Ressourcen fest, bis die JVM beendet ist — verhindert frühes `Process`-Deallok und Lebensdauer-Probleme der Menüleisten-App.
private final class DetachedJavaProcessRegistry: @unchecked Sendable {
    static let shared = DetachedJavaProcessRegistry()
    private let lock = NSLock()

    private enum Held {
        /// Stdout/Stderr → Logdatei (ohne Konsole).
        case detached(process: Process, log: FileHandle)
        /// Stdout/Stderr → Pipes + optionales Ausgabefenster (mit Konsole).
        case console(
            process: Process,
            out: Pipe,
            err: Pipe,
            showConsole: Bool,
            log: (String) -> Void
        )
    }

    private var entries: [Held] = []

    func addDetached(process: Process, logHandle: FileHandle) {
        lock.lock()
        entries.append(.detached(process: process, log: logHandle))
        lock.unlock()
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                DetachedJavaProcessRegistry.shared.onProcessTerminated(proc)
            }
        }
    }

    func addConsole(process: Process, out: Pipe, err: Pipe, showConsole: Bool, log: @escaping (String) -> Void) {
        lock.lock()
        entries.append(.console(process: process, out: out, err: err, showConsole: showConsole, log: log))
        lock.unlock()
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                DetachedJavaProcessRegistry.shared.onProcessTerminated(proc)
            }
        }
    }

    private func onProcessTerminated(_ proc: Process) {
        guard let held = takeEntry(for: proc) else { return }
        switch held {
        case .detached(_, let log):
            try? log.close()
        case .console(_, let out, let err, let showConsole, let log):
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            LaunchCoordinator.drainPipeRemainder(pipe: out, log: log)
            LaunchCoordinator.drainPipeRemainder(pipe: err, log: log)
            let code = proc.terminationStatus
            if showConsole {
                if code != 0 {
                    JavaProcessOutputWindow.shared.present()
                }
                JavaProcessOutputWindow.shared.appendFooter(exitCode: code)
            }
        }
    }

    private func takeEntry(for proc: Process) -> Held? {
        lock.lock()
        defer { lock.unlock() }
        guard let i = entries.firstIndex(where: {
            switch $0 {
            case .detached(let p, _): return p === proc
            case .console(let p, _, _, _, _): return p === proc
            }
        }) else { return nil }
        return entries.remove(at: i)
    }
}

/// Orchestrierung: Broker laden, JARs cachen, Java starten — Port von `LaunchService`.
enum LaunchCoordinator {
    /// Kurz warten nach `Process.run`, bis `isRunning` zuverlässig gesetzt ist (sonst fälschlicher sofortiger Fehlerpfad).
    private static let javaProcessPostRunHandshakeWait: TimeInterval = 0.28

    static func filterOsArchitecture(jarFiles: [ApiJarFile], jvmArch: String?) -> [ApiJarFile] {
        let osFiltered = jarFiles.filter { jar in
            guard let os = jar.Os?.trimmingCharacters(in: .whitespacesAndNewlines), !os.isEmpty else {
                return true
            }
            let o = os.lowercased()
            if o == "windows" { return false }
            return o.contains("mac") || o.contains("darwin") || o.contains("osx") || o == "macos"
        }
        guard let arch = jvmArch, !arch.isEmpty else { return osFiltered }
        return osFiltered.filter { jar in
            guard let ja = jar.Architecture?.trimmingCharacters(in: .whitespacesAndNewlines), !ja.isEmpty else {
                return true
            }
            let j = ja.lowercased()
            let a = arch.lowercased()
            if j == a { return true }
            if (a == "aarch64" && j == "arm64") || (a == "arm64" && j == "aarch64") { return true }
            return false
        }
    }

    static func run(
        launch: LaunchParameters,
        settings: LauncherSettings,
        log: @escaping @Sendable (String) -> Void,
        versionContinue: @escaping @Sendable (_ required: String, _ installed: String) async -> Bool
    ) async throws {
        AppPaths.migrateLegacyDirectoriesIfNeeded()
        let brokerPayload = try await BrokerFetcher.downloadJarDownloadPayload(brokerBase: launch.broker)
        let jsonText = String(data: brokerPayload, encoding: .utf8) ?? ""
        try JarCache.saveBrokerJson(brokerUrl: launch.broker, json: jsonText)
        let brokerInfo = try JSONFlexible.decodeJarDownload(data: brokerPayload)

        switch VersionPolicy.evaluateLauncherMinVersion(brokerInfo.LauncherMinVersion) {
        case .ok:
            break
        case .mustUpdate(let req, let ins):
            throw NSError(
                domain: "TradeERPLauncher",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "enventa Trade ERP Launcher muss aktualisiert werden (min. \(req), installiert \(ins))."]
            )
        case .shouldAskToContinue(let req, let ins):
            let ok = await versionContinue(req, ins)
            if !ok { throw CancellationError() }
        }

        let javaVersion = try JavaRuntimeResolver.pickJavaVersion(
            javaVersions: brokerInfo.JavaVersions ?? [],
            settings: settings
        )
        log(
            "Gewählte Java-Hauptversion: \(javaVersion) (Einstellung „\(settings.UseJavaVersion.rawValue)“).\n"
        )
        let runtime = try JavaRuntimeResolver.resolveRuntime(version: javaVersion, settings: settings)
        let rawArch = JavaRuntimeResolver.readJvmArchitecture(javaExecutable: runtime.javaExecutable)
        let arch = JavaRuntimeResolver.normalizedBrokerArchitecture(fromJvmOsArch: rawArch)

        let brokerRoot = try BrokerFetcher.normalizedBrokerURL(launch.broker)
        let baseJarUri = brokerRoot.appendingPathComponent("javaclient", isDirectory: true)

        let jars = brokerInfo.JarFiles ?? []
        let toDownload = filterOsArchitecture(jarFiles: jars, jvmArch: arch)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for jar in toDownload {
                group.addTask {
                    try await JarCache.downloadJar(baseJarUri: baseJarUri, jar: jar)
                }
            }
            try await group.waitForAll()
        }

        if let splash = brokerInfo.SplashImage, !splash.isEmpty {
            Task.detached {
                await downloadSplashIfNeeded(broker: launch.broker, relativePath: splash)
            }
        }

        try startJavaClient(
            brokerInfo: brokerInfo,
            launch: launch,
            settings: settings,
            runtime: runtime,
            arch: arch,
            detachAfterStart: !settings.DisplayConsole,
            log: log
        )
    }

    private static func downloadSplashIfNeeded(broker: String, relativePath: String) async {
        do {
            let brokerURL = (try? BrokerFetcher.normalizedBrokerURL(broker)) ?? URL(string: broker) ?? URL(fileURLWithPath: broker)
            let imageURL = URL(string: relativePath, relativeTo: brokerURL)?.absoluteURL ?? brokerURL.appendingPathComponent(relativePath)
            guard BrokerFetcher.isPermittedOutboundDownloadURL(imageURL) else { return }
            let name = JarCache.escapeBrokerName(broker)
            let dir = AppPaths.jarCacheDirectory
                .appendingPathComponent("files", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("SplashImage.png")
            try? FileManager.default.removeItem(at: dest)
            let req = URLRequest(url: imageURL)
            let (data, resp) = try await BrokerFetcher.sharedOutboundURLSession().data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return }
            try data.write(to: dest)
        } catch {
            // optional — wie TraceWarning im Original
        }
    }

    private static func startJavaClient(
        brokerInfo: ApiJarDownload,
        launch: LaunchParameters,
        settings: LauncherSettings,
        runtime: JavaRuntimeResolver.Resolved,
        arch: String?,
        detachAfterStart: Bool,
        log: @escaping (String) -> Void
    ) throws {
        var vm: [String] = []
        vm.append(contentsOf: brokerInfo.JavaProperties ?? [])
        stripDisplayConsoleSystemProperties(&vm)
        vm.append("-D\(LaunchParameterKey.displayConsole)=\(settings.DisplayConsole ? "true" : "false")")
        switch settings.ProxyMode {
        case .Direct:
            vm.append("-Djava.net.useSystemProxies=false")
        case .Windows:
            vm.append("-Djava.net.useSystemProxies=true")
        }
        vm.append(contentsOf: settings.JavaVmArguments)
        vm.append(contentsOf: runtime.vmArguments)

        let dockTitleRaw = launch.args[LaunchParameterKey.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dockName = dockTitleRaw.isEmpty ? "FS Client" : dockTitleRaw
        vm.append("-Xdock:name=\(dockName)")
        // Nur aus gebündeltem `Icon.png` (nicht `AppIcon.icns` — das ist das Launcher-Symbol mit den grünen Balken).
        if let dockPng = LauncherBrandingImages.writeJavaDockIconPNGFromBundleIfNeeded(), !dockPng.isEmpty {
            vm.append("-Xdock:icon=\(dockPng)")
        }
        // Menüleisten-Titel (macOS) an Dock-Namen angleichen, sofern der Broker nichts setzt (vgl. FlatLaf macOS).
        if !vm.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-Dapple.awt.application.name=") }) {
            vm.append("-Dapple.awt.application.name=\(dockName)")
        }

        let jars = brokerInfo.JarFiles ?? []
        let mainClass = brokerInfo.MainClass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cpJars: [ApiJarFile]
        if mainClass.isEmpty {
            cpJars = filterOsArchitecture(jarFiles: jars.filter { $0.isMainJar }, jvmArch: arch)
        } else {
            cpJars = filterOsArchitecture(jarFiles: jars, jvmArch: arch)
        }
        let cp = cpJars.map { $0.Sha1 + ".jar" }.joined(separator: ":")

        var args: [String] = []
        args.append(contentsOf: vm)
        args.append("-cp")
        args.append(cp)
        if mainClass.isEmpty {
            guard let mainJar = cpJars.first(where: { $0.isMainJar }) ?? cpJars.first else {
                throw LaunchError.noMainJar
            }
            args.append("-jar")
            args.append(mainJar.Sha1 + ".jar")
        } else {
            args.append(mainClass)
        }
        var clientArgs = buildClientArgs(brokerInfo: brokerInfo, launch: launch)
        if brokerClientUsesKeyValueProgramArgs(brokerInfo: brokerInfo) {
            clientArgs.removeAll { arg in
                let key = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
                return key.lowercased() == "displayconsole"
            }
            clientArgs.append(
                "\(LaunchParameterKey.displayConsole)=\(settings.DisplayConsole ? "True" : "False")"
            )
        }
        args.append(contentsOf: clientArgs)

        let jarDir = AppPaths.jarDirectory
        var nativePrefixes: [String] = []
        for jar in cpJars where jar.isNativeLib {
            nativePrefixes.append(jarDir.appendingPathComponent(jar.Sha1, isDirectory: true).path)
        }

        var env = ProcessInfo.processInfo.environment
        if !nativePrefixes.isEmpty {
            let prefix = nativePrefixes.joined(separator: ":")
            env["PATH"] = prefix + ":" + (env["PATH"] ?? "")
        }

        log(
            """
            Java: \(runtime.javaExecutable.path)
            Arbeitsverzeichnis: \(jarDir.path)
            Argumente: \(args.joined(separator: " "))

            """
        )

        let cacheDays = settings.CacheCleanDays
        Task.detached {
            CacheCleanup.cleanupCache(days: nil, cacheCleanDays: cacheDays)
        }

        if detachAfterStart {
            try startJavaClientDetached(
                javaPath: runtime.javaExecutable.path,
                javaArguments: args,
                jarDir: jarDir,
                environment: env,
                log: log
            )
        } else {
            let p = Process()
            p.executableURL = runtime.javaExecutable
            p.arguments = args
            p.currentDirectoryURL = jarDir
            p.environment = env

            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err

            try p.run()
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                if let s = String(data: d, encoding: .utf8), !s.isEmpty { log(s) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                if let s = String(data: d, encoding: .utf8), !s.isEmpty { log(s) }
            }
            let showConsole = settings.DisplayConsole
            // `Process` + Pipes bis zum JVM-Ende im Registry halten; Aufräumen in `terminationHandler` auf dem Main Thread
            // (kein `waitUntilExit` in einem `Task.detached`, damit der Menüleisten-Launcher nicht mit beendet wird).
            DetachedJavaProcessRegistry.shared.addConsole(
                process: p,
                out: out,
                err: err,
                showConsole: showConsole,
                log: log
            )
        }
    }

    /// Startet **java** direkt als Kindprozess (ohne `bash`), leitet Ausgabe in eine Logdatei und **hält** `Process` + `FileHandle`, damit der Launcher nicht beendet wird und keine Pipes offen bleiben.
    private static func startJavaClientDetached(
        javaPath: String,
        javaArguments: [String],
        jarDir: URL,
        environment: [String: String],
        log: @escaping (String) -> Void
    ) throws {
        try FileManager.default.createDirectory(at: AppPaths.logFilesDirectory, withIntermediateDirectories: true)
        let logURL = AppPaths.logFilesDirectory.appendingPathComponent("java-client-output.log", isDirectory: false)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: javaPath)
        p.arguments = javaArguments
        p.currentDirectoryURL = jarDir
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = logHandle
        p.standardError = logHandle

        try p.run()
        Thread.sleep(forTimeInterval: javaProcessPostRunHandshakeWait)
        if !p.isRunning {
            let code = p.terminationStatus
            try? logHandle.close()
            log("Java-Start fehlgeschlagen (Exit \(code)). Details in \(logURL.path)\n")
            throw LaunchError.clientExit(code)
        }
        DetachedJavaProcessRegistry.shared.addDetached(process: p, logHandle: logHandle)
        log("Java gestartet (ohne Konsole). Stdout/Stderr: \(logURL.path)\n")
    }

    private static func stripDisplayConsoleSystemProperties(_ vm: inout [String]) {
        vm.removeAll { token in
            let t = token.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("-DDisplayConsole=") || t.hasPrefix("-DdisplayConsole=")
        }
    }

    fileprivate static func drainPipeRemainder(pipe: Pipe, log: (String) -> Void) {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if data.isEmpty { return }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            log(s)
        }
    }

    /// Ab Broker-Version 4.8: `key=value`-Programmargumente (u. a. `displayConsole`).
    private static func brokerClientUsesKeyValueProgramArgs(brokerInfo: ApiJarDownload) -> Bool {
        guard let minRaw = brokerInfo.LauncherMinVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !minRaw.isEmpty,
              let minV = VersionPolicy.Semantic.parse(minRaw) else {
            return false
        }
        return minV.major > 4 || (minV.major == 4 && minV.minor >= 8)
    }

    /// `GetClientArgs` aus `LaunchService`.
    private static func buildClientArgs(brokerInfo: ApiJarDownload, launch: LaunchParameters) -> [String] {
        guard let minRaw = brokerInfo.LauncherMinVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            !minRaw.isEmpty,
            let minV = VersionPolicy.Semantic.parse(minRaw) else {
            return []
        }
        if minV.major < 4 || (minV.major == 4 && minV.minor < 8) {
            let prefix = launch.support ? "SUPPORT|" : ""
            let devBrokerField = (brokerInfo.DevBroker == true) ? "True" : "False"
            return [
                "true",
                prefix + devBrokerField,
                launch.broker,
                launch.lookAndFeel,
                launch.language,
                launch.theme,
                String(launch.noDomainAuth),
                brokerInfo.SplashImage ?? "",
            ]
        }
        var list: [String] = []
        if launch.args[LaunchParameterKey.devBroker] == nil {
            list.append("\(LaunchParameterKey.devBroker)=\((brokerInfo.DevBroker == true) ? "True" : "False")")
        }
        if launch.args[LaunchParameterKey.splashImage] == nil, let sp = brokerInfo.SplashImage {
            list.append("\(LaunchParameterKey.splashImage)=\(sp)")
        }
        for (k, v) in launch.args {
            list.append("\(k)=\(v)")
        }
        return list
    }
}
