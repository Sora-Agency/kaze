import SwiftUI
import AppKit

struct PreviewLaunchRunner: LaunchCommandRunning {
    func run(_ arguments: [String]) throws -> LaunchCommandResult { LaunchCommandResult(status: 113, output: "") }
}

@main
struct Preview {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fm = FileManager.default
        let languageSuite = "kaze.preview.\(UUID())"
        let languageDefaults = UserDefaults(suiteName: languageSuite)!
        let language = AppLanguageStore(defaults: languageDefaults)
        defer { languageDefaults.removePersistentDomain(forName: languageSuite) }
        let root = fm.temporaryDirectory.appendingPathComponent("Kaze-Preview-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let home = PreviewFixtures.home
        let folder = CommandLine.arguments.contains("--caches") ? home.appendingPathComponent("Library") : home.appendingPathComponent("Downloads")
        let model = CleanerModel(scanOnLaunch: false, initialStorage: PreviewFixtures.storage, readsLogs: false,
                                 logURL: root.appendingPathComponent("preview.log"))
        let explorer = FileExplorerModel(folder: folder, home: home, initialEntries: PreviewFixtures.entries(in: folder))
        let isEditor = CommandLine.arguments.contains("--editor")
        let width = isEditor ? 740 : CommandLine.arguments.contains("--compact") ? 1130 : 1280
        let height = isEditor ? (CommandLine.arguments.contains("--full-editor") ? 950 : 680) : 860
        let dark = CommandLine.arguments.contains("--dark")
        let section: AppSection = CommandLine.arguments.contains("--legal") ? .legal
            : CommandLine.arguments.contains("--scheduled") ? .scheduled
            : CommandLine.arguments.contains("--cleanup") ? .cleanup : .explorer
        let resources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("package/Kaze.app/Contents/Resources")
        if CommandLine.arguments.contains("--scheduled") {
            var daily = ScheduledCleanupTask.preset
            daily.configuration.developmentCaches = false; daily.configuration.dockerCaches = false
            var development = ScheduledCleanupTask(name: L10n.text("Desarrollo al terminar el día"))
            development.configuration.hour = 18; development.configuration.minute = 0
            development.configuration.frequency = .weekdays
            development.configuration.generalCaches = false; development.configuration.dockerCaches = false
            var docker = ScheduledCleanupTask(name: L10n.text("Docker del fin de semana"))
            docker.configuration.hour = 2; docker.configuration.minute = 0
            docker.configuration.frequency = .weekly; docker.configuration.weekday = 7
            docker.configuration.generalCaches = false; docker.configuration.developmentCaches = false
            let url = root.appendingPathComponent("Library/Application Support/Kaze/schedule.json")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ScheduleCollection(tasks: [daily, development, docker])).write(to: url)
        }
        let scheduler = ScheduledTaskModel(service: ScheduleService(home: root, scriptURL: resources.appendingPathComponent("cleaner.zsh"), runner: PreviewLaunchRunner()), inspectSystem: false)

        let rootView = ContentView(model: model, explorer: explorer, scheduler: scheduler, previewAppearance: dark ? .dark : .light,
                                   initialSection: section, resourceDirectory: resources, homeURL: home, languageStore: language,
                                   diskAccessStore: DiskAccessStore(initialStatus: CommandLine.arguments.contains("--access-granted") ? .available : .restricted))
        SoraFonts.register(directory: resources.appendingPathComponent("Fonts"))
        var edited = scheduler.tasks.last ?? ScheduledCleanupTask()
        if CommandLine.arguments.contains("--weekly") { edited.configuration.frequency = .weekly }
        if CommandLine.arguments.contains("--inactive-condition") { edited.configuration.onlyWhenLowSpace = false }
        let shown = isEditor
            ? AnyView(ScheduleTaskEditor(model: scheduler, task: edited, isNew: true, onCancel: {}, onSaved: {}, height: CGFloat(height))
                .preferredColorScheme(dark ? .dark : .light))
            : AnyView(rootView)
        let hosting = NSHostingView(rootView: shown.environment(\.locale, L10n.locale))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        let deadline = Date().addingTimeInterval(4)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        while section == .explorer && (!explorer.hasLoaded || explorer.isScanning) && Date() < deadline
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        if CommandLine.arguments.contains("--switch-language") {
            language.select(language.selection == .spanish ? .english : .spanish)
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        }
        if CommandLine.arguments.contains("--focus-input") {
            func firstTextField(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                for child in view.subviews { if let field = firstTextField(child) { return field } }
                return nil
            }
            guard let field = firstTextField(hosting), window.makeFirstResponder(field) else {
                fatalError("No se pudo enfocar el campo de texto")
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        window.orderOut(nil)
        print("Preview rendered at \(width) × \(height)")
    }
}
