import Foundation

@main
struct PreviewPrivacyTests {
    @MainActor
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("kaze-preview-privacy-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let log = root.appendingPathComponent("private.log")
        try Data("PRIVATE_RECORD_MUST_NOT_APPEAR".utf8).write(to: log)
        let cleaner = CleanerModel(scanOnLaunch: false, initialStorage: PreviewFixtures.storage, readsLogs: false, logURL: log)
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            print("PASS: \(message)")
        }
        check(cleaner.storage.total == 512_000_000_000 && cleaner.storage.free == 164_000_000_000,
              "Public previews use seeded storage instead of host disk statistics")
        check(cleaner.applications.isEmpty && cleaner.managedResources.isEmpty,
              "Public previews skip application and resource discovery")
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        check(cleaner.logText.isEmpty, "Disabled log reading stays disabled after the polling interval")
        let logContents = try Data(contentsOf: log)
        check(String(data: logContents, encoding: .utf8) == "PRIVATE_RECORD_MUST_NOT_APPEAR",
              "Rendering models do not write to existing logs")
        let folder = root.appendingPathComponent("Downloads")
        let entries = PreviewFixtures.entries(in: folder)
        let explorer = FileExplorerModel(folder: folder, home: root, initialEntries: entries)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(explorer.hasLoaded && !explorer.isScanning && explorer.error == nil,
              "Seeded explorer renders without reading a directory")
        check(!manager.fileExists(atPath: folder.path) && explorer.entries.count == 7 && explorer.totalBytes == 10_882_032_000,
              "Fictitious multi-gigabyte files require no on-disk payloads")
        let library = PreviewFixtures.entries(in: PreviewFixtures.home.appendingPathComponent("Library"))
        check(library.first { $0.name == "Caches" }?.deletion.safety == .regenerable,
              "Public cache example keeps its regenerable classification")
        check(library.first { $0.name == "Preferences" }?.deletion.safety == .sensitive,
              "Public preferences example keeps its sensitive classification")
    }
}
