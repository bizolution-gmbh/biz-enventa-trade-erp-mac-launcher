import Foundation

/// Orchestrierung: Broker laden, JARs cachen, Java starten — Port von `LaunchService`.
enum LaunchCoordinator {
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
        launch: ApiFsClient,
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
                domain: "FSClientLauncher",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "FS Client Launcher muss aktualisiert werden (min. \(req), installiert \(ins))."]
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
            let name = JarCache.escapeBrokerName(broker)
            let dir = AppPaths.jarCacheDirectory
                .appendingPathComponent("files", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("SplashImage.png")
            try? FileManager.default.removeItem(at: dest)
            let req = URLRequest(url: imageURL)
            let (data, resp) = try await URLSession(configuration: BrokerFetcher.urlSessionConfiguration()).data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return }
            try data.write(to: dest)
        } catch {
            // optional — wie TraceWarning im Original
        }
    }

    /// Ein Argument für `bash -c` (POSIX: alles in einfache Anführungszeichen, `'` als `'\''`).
    private static func shellSingleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func startJavaClient(
        brokerInfo: ApiJarDownload,
        launch: ApiFsClient,
        settings: LauncherSettings,
        runtime: JavaRuntimeResolver.Resolved,
        arch: String?,
        detachAfterStart: Bool,
        log: @escaping (String) -> Void
    ) throws {
        var vm: [String] = []
        vm.append(contentsOf: brokerInfo.JavaProperties ?? [])
        stripDisplayConsoleSystemProperties(&vm)
        vm.append("-D\(ApiFsClientKeys.displayConsole)=\(settings.DisplayConsole ? "true" : "false")")
        switch settings.ProxyMode {
        case .Direct:
            vm.append("-Djava.net.useSystemProxies=false")
        case .Windows:
            vm.append("-Djava.net.useSystemProxies=true")
        }
        vm.append(contentsOf: settings.JavaVmArguments)
        vm.append(contentsOf: runtime.vmArguments)

        let dockTitleRaw = launch.args[ApiFsClientKeys.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                "\(ApiFsClientKeys.displayConsole)=\(settings.DisplayConsole ? "True" : "False")"
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
            p.waitUntilExit()
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            drainPipeRemainder(pipe: out, log: log)
            drainPipeRemainder(pipe: err, log: log)
            let exitCode = p.terminationStatus
            if settings.DisplayConsole {
                JavaProcessOutputWindow.shared.appendFooter(exitCode: exitCode)
            }
            if exitCode != 0 {
                throw LaunchError.clientExit(exitCode)
            }
        }
    }

    /// Startet Java in einem kurzlebigen `bash`, damit der Kindprozess beim Beenden des Launchers nicht an Pipes hängt.
    /// Ohne `DisplayConsole`: Launcher kann sich beenden, im Menü bleibt die Swing-/JavaFX-App mit `-Xdock:name` sichtbar.
    private static func startJavaClientDetached(
        javaPath: String,
        javaArguments: [String],
        jarDir: URL,
        environment: [String: String],
        log: @escaping (String) -> Void
    ) throws {
        try FileManager.default.createDirectory(at: AppPaths.logFilesDirectory, withIntermediateDirectories: true)
        let logURL = AppPaths.logFilesDirectory.appendingPathComponent("java-client-output.log", isDirectory: false)

        let argv = ([javaPath] + javaArguments).map(shellSingleQuoted).joined(separator: " ")
        let qJar = shellSingleQuoted(jarDir.path)
        let qLog = shellSingleQuoted(logURL.path)
        // Nicht-interaktives bash beendet Hintergrundjobs beim Exit üblicherweise nicht mit SIGHUP.
        let script =
            "set -e; cd \(qJar) || exit 2; \(argv) >>\(qLog) 2>&1 & sleep 0.22; if kill -0 $! 2>/dev/null; then exit 0; fi; wait $!; exit $?"

        let bash = Process()
        bash.executableURL = URL(fileURLWithPath: "/bin/bash")
        bash.arguments = ["-c", script]
        bash.currentDirectoryURL = jarDir
        bash.environment = environment

        let out = Pipe()
        bash.standardOutput = out
        bash.standardError = out
        bash.standardInput = FileHandle.nullDevice

        try bash.run()
        bash.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if let tail = String(data: data, encoding: .utf8), !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log(tail)
        }
        let status = bash.terminationStatus
        if status != 0 {
            log(
                "Java-Start fehlgeschlagen (Exit \(status)). Details in \(logURL.path)\n"
            )
            throw LaunchError.clientExit(status)
        }
        log("Java gestartet (ohne Konsole). Stdout/Stderr: \(logURL.path)\n")
    }

    private static func stripDisplayConsoleSystemProperties(_ vm: inout [String]) {
        vm.removeAll { token in
            let t = token.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("-DDisplayConsole=") || t.hasPrefix("-DdisplayConsole=")
        }
    }

    private static func drainPipeRemainder(pipe: Pipe, log: (String) -> Void) {
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
    private static func buildClientArgs(brokerInfo: ApiJarDownload, launch: ApiFsClient) -> [String] {
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
        if launch.args[ApiFsClientKeys.devBroker] == nil {
            list.append("\(ApiFsClientKeys.devBroker)=\((brokerInfo.DevBroker == true) ? "True" : "False")")
        }
        if launch.args[ApiFsClientKeys.splashImage] == nil, let sp = brokerInfo.SplashImage {
            list.append("\(ApiFsClientKeys.splashImage)=\(sp)")
        }
        for (k, v) in launch.args {
            list.append("\(k)=\(v)")
        }
        return list
    }
}
