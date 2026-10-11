import Foundation

@main
struct DeletionSafetyTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("kaze-safety-\(UUID())")
        defer { try? fm.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches")
        let documents = home.appendingPathComponent("Documents")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        let classifier = DeletionClassifier(home: home)
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; print("PASS: \(message)")
        }
        func safety(_ path: String) -> DeletionSafety {
            classifier.assess(home.appendingPathComponent(path)).safety
        }
        check(safety("Library/Caches") == .regenerable && safety("Library/Caches/App/file.bin") == .regenerable, "Known cache root and descendants are regenerable")
        check(safety("Library/Developer/Xcode/DerivedData/Build") == .regenerable, "Xcode derived builds are regenerable")
        check(safety("Library/Developer/CoreSimulator/Caches/data") == .regenerable, "Simulator caches are regenerable")
        check(safety("Library/Caches-backup/personal.db") == .sensitive, "Similar prefixes cannot spoof a cache path")
        check(safety("Downloads/cache.zip") == .review && safety("Documents/log.txt") == .review, "Personal downloads and logs are never assumed safe")
        check(safety("Library") == .sensitive && safety("Library/Application Support/app/data") == .sensitive, "Mixed Library roots and app data are sensitive")
        check(safety(".ssh/key") == .sensitive && safety(".config/settings") == .sensitive, "Hidden credentials and configuration are sensitive")
        check(classifier.assess(URL(fileURLWithPath: "/System/Library" )).safety == .sensitive && classifier.assess(URL(fileURLWithPath: "/etc/hosts")).safety == .sensitive, "System paths and their aliases are sensitive")
        check(safety("Downloads/App.app") == .sensitive, "Application bundles are sensitive outside Applications too")
        check(classifier.assess(cache, metadataAvailable: false).safety == .review, "Unreadable metadata never earns a safe status")
        let link = cache.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: link, withDestinationURL: documents)
        check(classifier.assess(link, isSymbolicLink: true).safety == .review, "Symbolic links are always reviewed")
        check(classifier.assess(link.appendingPathComponent("notes.txt")).safety == .review, "A symlink parent cannot give documents a cache status")
        let rows = try DiskScanner.entries(at: home.appendingPathComponent("Library"), classifier: classifier)
        check(rows.first { $0.name == "Caches" }?.deletion.safety == .regenerable, "Scanner attaches the assessment to each row")
        let model = FileExplorerModel(folder: home.appendingPathComponent("Library"), home: home)
        model.scan()
        let deadline = Date().addingTimeInterval(5)
        while model.isScanning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(!model.isScanning && model.error == nil, "Assessment scan completes")
        let total = model.totalBytes
        model.safetyFilter = .regenerable
        check(model.visibleEntries.count == 1 && model.visibleEntries.first?.name == "Caches" && model.totalBytes == total, "Safety filters preserve the total folder size")
        model.safetyFilter = .sensitive
        check(model.visibleEntries.isEmpty, "Empty safety filters do not show unrelated files")
        model.safetyFilter = nil
        check(model.visibleEntries.count == model.entries.count, "All restores every listed entry")
        check(ExplorerLocation.active(for: home.appendingPathComponent("Downloads/Archive"), home: home) == .downloads, "Downloads stays active in subfolders")
        check(ExplorerLocation.active(for: home.appendingPathComponent("Downloads-backup"), home: home) == .home, "Location matching respects path boundaries")
        check(ExplorerLocation.active(for: home.appendingPathComponent("Documents"), home: home) == .documents, "Documents is selected instead of its Home parent")
        check(ExplorerLocation.active(for: home.appendingPathComponent("Desktop/Project"), home: home) == .desktop, "Desktop stays selected in subfolders")
        check(ExplorerLocation.active(for: URL(fileURLWithPath: "/Volumes/USB/Folder"), home: home) == .external, "External disks select the external location")
        check(ExplorerLocation.active(for: URL(fileURLWithPath: "/Applications"), home: home) == .disk, "Other internal locations select Macintosh HD")
        print("All deletion safety and location tests passed.")
    }
}
