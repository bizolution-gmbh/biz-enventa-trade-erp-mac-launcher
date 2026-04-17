import FSClientLauncherLib

@main
enum FSClientLauncherExecutable {
    @MainActor
    static func main() {
        FSClientLauncherEntry.main()
    }
}
