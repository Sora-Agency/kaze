import Foundation

@main
struct ExplorerModelTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory)).appendingPathComponent("kaze-model-\(UUID())")
        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let cacheDirectory = root.deletingLastPathComponent().appendingPathComponent("kaze-cache-\(UUID())")
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: cacheDirectory) }
        let one = nested.appendingPathComponent("one.bin")
        try Data(repeating: 1, count: 32_768).write(to: one)
        try fm.linkItem(at: one, to: root.appendingPathComponent("shared.bin"))
        let model = FileExplorerModel(folder: root, home: root,
            cache: AnalysisCache(home: root, directory: cacheDirectory))
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; print("PASS: \(message)")
        }
        func finish() {
            let deadline = Date().addingTimeInterval(5)
            while model.isScanning && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            check(!model.isScanning, "Async scan finishes")
        }
        model.scan(); finish()
        check(model.error == nil && model.entries.count == 2, "Initial folder is listed")
        check(model.entries.first { $0.isDirectory }?.measurement?.bytes ?? 0 > 0, "Folder total appears before entering")
        check(model.totalBytes == DiskScanner.measure(root, cancellation: ScanCancellation()).bytes, "Parent total deduplicates hard links across children")
        model.filter = .folders
        check(model.visibleEntries.count == 1, "Filter does not change total or listed entries")
        model.filter = .all; model.search = "shared"
        check(model.visibleEntries.count == 1, "Search filters current folder")
        model.open(nested); finish()
        check(model.search.isEmpty && model.backHistory.last?.path == root.path, "Navigation resets search and records history")
        model.back(); finish()
        check(model.folder.path == root.path && model.forwardHistory.last?.path == nested.path, "Back restores previous folder")
        model.forward(); finish()
        check(model.folder.path == nested.path, "Forward restores next folder")
        model.open(root.appendingPathComponent("missing"))
        model.open(root); finish()
        check(model.error == nil && model.entries.count == 2, "A stale failure cannot overwrite a newer scan")
        model.scan(); model.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(model.cancelled && !model.isScanning && model.entries.count == 2, "Stop rejects late updates and preserves visible results")
        model.scan(); finish()
        check(model.incompleteCount == 0 && !model.cancelled, "Refresh completes a stopped scan")
        print("All explorer model tests passed.")
    }
}
