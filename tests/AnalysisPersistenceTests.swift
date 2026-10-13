import Foundation

@main
struct AnalysisPersistenceTests {
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label); print("PASS: \(label)")
    }
    static func main() throws {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory), isDirectory: true)
            .appendingPathComponent("kaze-persistence-\(UUID())")
        let a = home.appendingPathComponent("Documents/A"), b = home.appendingPathComponent("Documents/B")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        for number in 0..<100 {
            try Data("fixture".utf8).write(to: a.appendingPathComponent("file-\(number)-" + String(repeating: "x", count: 80)))
        }
        try Data("other volume root fixture".utf8).write(to: b.appendingPathComponent("keep"))
        let index = StorageIndexer.scan(roots: [a, b], home: home, cancellation: ScanCancellation())
        let value = CachedStorageAnalysis(schema: 1, index: index, duplicates: .init(), snapshots: [], snapshotStatus: "fixture")
        let legacy = home.appendingPathComponent("Library/Caches/Kaze/Analysis-v1")
        let old = AnalysisCache(home: home, directory: legacy)
        check(old.saveAnalysis(value), "Fixture saves a legacy baseline")
        let durable = AnalysisCache(home: home)
        check(durable.loadAnalysis(home: home)?.index.allocated == index.allocated,
              "Legacy Smart Scan migrates into durable app data without changing totals")
        try fm.removeItem(at: legacy)
        check(AnalysisCache(home: home).loadAnalysis(home: home)?.index.date == index.date,
              "Clearing disposable caches cannot erase the durable baseline")
        let small = AnalysisCache(home: home, directory: home.appendingPathComponent("SmallCache"), scanLimit: 4096, budget: 8192)
        check(small.saveAnalysis(value), "Oversized snapshots are compacted instead of silently discarded")
        let compacted = small.loadAnalysis(home: home)!
        check(compacted.index.files.count < index.files.count && compacted.index.roots == index.roots
            && compacted.index.allocated == index.allocated && compacted.index.logical == index.logical,
              "Compaction retains every root and its full logical and allocated totals")
        check(compacted.index.omitted > 0 && compacted.duplicates.partial
            && compacted.index.files.filter { $0.parent == nil }.allSatisfy(\.detailsLimited),
              "Compacted detail and duplicate coverage are disclosed as limited")
        let smart = small.directory.appendingPathComponent("smart.plist")
        try fm.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: smart.path)
        let classifier = DeletionClassifier(home: home)
        let folder = try ExplorerSnapshotBuilder.refresh(folder: a, previous: nil, changes: .init(), force: true,
            checkpoint: FolderChangeMonitor.eventID(), cancellation: ScanCancellation(), classifier: classifier)
        small.saveFolder(folder)
        check(small.loadAnalysis(home: home)?.index.date == index.date,
              "A newer Explorer record never evicts an older Smart Scan")
        let size = try fm.contentsOfDirectory(at: small.directory, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        check(size <= 8192, "Protected baselines still respect the total storage budget")
        let docs = home.appendingPathComponent("Documents")
        var measured: [String] = []
        let measure: ExplorerSnapshotBuilder.Measure = { url, token, count in
            measured.append(url.lastPathComponent)
            var result = DiskScanner.measure(url, cancellation: token, counted: count)
            if url.lastPathComponent == "A" { result.unreadableCount = 1 }
            return result
        }
        let partial = try ExplorerSnapshotBuilder.refresh(folder: docs, previous: nil, changes: .init(), force: true,
            checkpoint: FolderChangeMonitor.eventID(), cancellation: ScanCancellation(), classifier: classifier, measure: measure)
        measured = []
        _ = try ExplorerSnapshotBuilder.refresh(folder: docs, previous: partial, changes: .init(), force: false,
            checkpoint: partial.eventID, cancellation: ScanCancellation(), classifier: classifier, measure: measure)
        check(measured.isEmpty && !partial.complete, "An unchanged inaccessible branch does not trigger another full walk")
        _ = try ExplorerSnapshotBuilder.refresh(folder: docs, previous: partial, changes: FolderChanges(paths: [b.appendingPathComponent("keep").path]), force: false,
            checkpoint: partial.eventID, cancellation: ScanCancellation(), classifier: classifier, measure: measure)
        check(measured == ["B"], "Changes still update the affected branch of a partially readable folder")
        var checkpoint: CachedExplorerFolder?
        let canceled = ScanCancellation()
        do {
            _ = try ExplorerSnapshotBuilder.refresh(folder: docs, previous: partial, changes: .init(), force: true,
                checkpoint: partial.eventID, cancellation: canceled, classifier: classifier,
                checkpointed: { point in checkpoint = point; canceled.cancel() }, measure: measure)
        } catch { }
        check(checkpoint?.hasPendingMeasurements == true,
              "An interrupted refresh marks old measurements as unfinished rather than fresh")
        if let checkpoint {
            small.saveFolder(checkpoint)
            check(small.loadFolder(docs)?.hasPendingMeasurements == true,
                  "Interrupted refresh keeps a savable dated browsing baseline")
        }
        var large = partial
        large.entries[0] = CachedExplorerEntry(url: partial.entries[0].url, directory: true, symbolicLink: false,
            modified: nil, fingerprint: partial.entries[0].fingerprint, measurement: DiskMeasurement(fileCount: 50_000))
        check(ExplorerRefreshPolicy.deferAutomaticRefresh(large) && !ExplorerRefreshPolicy.deferAutomaticRefresh(partial),
              "Large tree changes request an explicit refresh while small folders retain live updates")
        let blocked = home.appendingPathComponent("NotADirectory")
        try Data("fixture".utf8).write(to: blocked)
        check(!AnalysisCache(home: home, directory: blocked).saveAnalysis(value),
              "Persistence failure is reported instead of claiming the baseline was saved")
    }
}
