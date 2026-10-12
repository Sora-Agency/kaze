import Foundation

@main
struct SmartScanModelTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory), isDirectory: true).appendingPathComponent("kaze-model-analysis-\(UUID())")
        let docs = root.appendingPathComponent("Documents")
        let other = root.appendingPathComponent("Other")
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let cacheDirectory = root.deletingLastPathComponent().appendingPathComponent("kaze-smart-cache-\(UUID())")
        let cache = AnalysisCache(home: root, directory: cacheDirectory)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: cacheDirectory) }
        for name in ["first.txt", "copy.txt"] { try Data("same contents".utf8).write(to: docs.appendingPathComponent(name)) }
        let resources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src")
        let model = SmartScanModel(home: root, resources: resources, cache: cache)
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); print("PASS: \(message)") }
        func finish() {
            let deadline = Date().addingTimeInterval(10)
            while model.busy, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(!model.busy, "Analysis work completes off the main actor")
        }
        check(!model.isScanning && model.index.files.isEmpty, "Smart Scan never starts a filesystem walk on launch")
        model.scan(roots: [root]); model.stop(); model.scan(roots: [other], includeDuplicates: false); finish()
        check(model.index.roots.map(\.path) == [other.path] && model.error == nil, "A cancelled generation cannot replace the newest analysis")
        model.scan(roots: [root]); finish()
        check(model.duplicates.exact.count == 1 && model.snapshots.isEmpty, "A folder scan shares exact duplicates without consulting host snapshots")
        let savedDate = model.index.date
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(10)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(condition(), "Cache background work completes")
        }
        wait { cache.loadAnalysis(home: root)?.index.date == savedDate }
        let restored = SmartScanModel(home: root, resources: resources, cache: cache)
        wait { !restored.isRestoring }
        check(!restored.isScanning && restored.index.date == savedDate && restored.duplicates.exact.count == 1,
              "New app sessions restore the index and duplicates without walking or hashing files")
        check(restored.showingCached && restored.isStale && restored.selected.isEmpty && restored.duplicateSelection.isEmpty
            && !restored.canSelectDuplicate(restored.duplicates.exact[0].nodes[1]),
              "Restored results are dated display data and cannot authorize deletion")
        let firstEntry = FileExplorerModel(folder: docs, home: root, cache: cache)
        firstEntry.sharedIndex = model.index; firstEntry.loadIfNeeded()
        check(firstEntry.entries.count == 2 && firstEntry.measuredAt == model.index.date,
              "The first Explorer entry reuses Smart Scan immediately")
        firstEntry.stop()
        let raced = SmartScanModel(home: root, resources: resources, cache: cache)
        raced.scan(roots: [other], includeDuplicates: false)
        wait { !raced.isScanning }
        check(raced.index.roots.map(\.path) == [other.path] && !raced.showingCached,
              "A late cache restore cannot replace a newly requested scan")
        let explorer = FileExplorerModel(folder: other, home: root, initialEntries: [])
        explorer.sharedIndex = model.index; explorer.open(docs)
        check(!explorer.isScanning && explorer.entries.count == 2 && explorer.status.contains("Smart Scan"), "Explorer reuses complete recent folder measurements without rescanning")
        let copy = model.duplicates.exact[0].nodes[1]
        model.duplicateSelection = [copy]; model.markChanged()
        check(model.isStale && !model.canSelectDuplicate(copy) && model.duplicateSelection.isEmpty, "A mutation invalidates selection until a fresh analysis")
        wait { cache.loadAnalysis(home: root) == nil }
        let invalidated = SmartScanModel(home: root, resources: resources, cache: cache)
        wait { !invalidated.isRestoring }
        check(invalidated.index.files.isEmpty, "Invalidation prevents deleted analysis data from returning on restart")
        model.scan(roots: [root], includeDuplicates: false); finish()
        check(!model.isStale && model.duplicates.exact.isEmpty, "Fresh analysis resets stale results and duplicate selections")
        print("Smart Scan model integration tests passed using temporary data only.")
    }
}
