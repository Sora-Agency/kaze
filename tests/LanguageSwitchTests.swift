import SwiftUI
import AppKit

@main
struct LanguageSwitchTests {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "kaze.language-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let initial = AppLanguage(rawValue: L10n.language)!
        defer {
            L10n.select(initial, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let language = AppLanguageStore(defaults: defaults)
        language.select(.english)
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message)")
        }
        defaults.set(["en-US"], forKey: "AppleLanguages")
        language.select(.spanish)
        check(L10n.initialLanguage(defaults: defaults, environment: [:]) == "es", "Saved in-app language overrides macOS preferences on restart")
        check(AppLanguageStore(defaults: defaults).selection == .spanish, "New windows share the selected language")
        defaults.set("unsupported", forKey: L10n.preferenceKey)
        check(L10n.initialLanguage(defaults: defaults, environment: [:]) == "en", "Invalid saved language falls back to macOS preferences")
        language.select(.english)
        let folder = PreviewFixtures.home.appendingPathComponent("Downloads")
        let explorer = FileExplorerModel(folder: folder, home: PreviewFixtures.home, initialEntries: PreviewFixtures.entries(in: folder))
        explorer.search = "Example"
        explorer.order = .name
        let cleaner = CleanerModel(scanOnLaunch: false, initialStorage: PreviewFixtures.storage, readsLogs: false)
        let assessment = DeletionClassifier(home: PreviewFixtures.home).assess(PreviewFixtures.home.appendingPathComponent("Library/Caches"))
        let task = ScheduledCleanupTask(name: "Mi tarea personal")
        let files = explorer.entries.map(\.id)
        let total = explorer.totalBytes
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(task)
        let englishExplanation = assessment.explanation
        language.select(.spanish)
        check(explorer.status == "Análisis completo · 7 elementos", "Existing scan status switches language without rescanning")
        check(cleaner.progressMessage == "Listo para limpiar" && cleaner.dockerStatus == "Sin analizar", "Existing cleanup and Docker status switches language")
        check(assessment.explanation != englishExplanation && assessment.safety == .regenerable, "Safety explanations switch language without reclassifying files")
        check(explorer.entries.map(\.id) == files && explorer.totalBytes == total && !explorer.isScanning && explorer.order == .name && explorer.search == "Example", "Language changes preserve files, totals, filters and sort order")
        check(try encoder.encode(task) == data && task.name == "Mi tarea personal", "Language changes preserve task names and configuration")

        func heading(in view: NSView) throws -> Data {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot capture the rendered interface") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let image = bitmap.cgImage,
                  let heading = image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: 100 * CGFloat(image.height) / view.bounds.height)),
                  let data = NSBitmapImageRep(cgImage: heading).representation(using: .png, properties: [:]) else {
                fatalError("Cannot read the rendered interface")
            }
            return data
        }
        func settledHeading(in view: NSView) throws -> Data {
            let deadline = Date().addingTimeInterval(5)
            var previous = try heading(in: view)
            var stableFrames = 0
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let current = try heading(in: view)
                stableFrames = current == previous ? stableFrames + 1 : 0
                if stableFrames == 3 { return current }
                previous = current
            }
            fatalError("Rendered heading did not settle")
        }
        SoraFonts.register(directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("src/Fonts"))
        let hosting = NSHostingView(rootView: DashboardView(model: cleaner)
            .preferredColorScheme(.light)
            .transaction { $0.disablesAnimations = true; $0.animation = nil })
        hosting.frame = NSRect(x: 0, y: 0, width: 950, height: 720)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        let spanish = try settledHeading(in: hosting)
        language.select(.english)
        let english = try settledHeading(in: hosting)
        check(english != spanish, "Rendered heading switches instantly without recreating the window")
        language.select(.spanish)
        check(try settledHeading(in: hosting) == spanish, "Rendered heading returns to Spanish in the same window")
        window.orderOut(nil)
        print("Language switching tests passed.")
    }
}
