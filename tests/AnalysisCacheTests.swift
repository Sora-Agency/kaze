import Foundation
import Combine
import Darwin

@main
struct AnalysisCacheTests {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".kaze-cache-tests-\(UUID())")
        let home = root.appendingPathComponent("home"), data = home.appendingPathComponent("Documents")
        let a = data.appendingPathComponent("A"), b = data.appendingPathComponent("B")
        let deep = a.appendingPathComponent("nested/deep"), cacheDirectory = root.appendingPathComponent("cache")
        let cache = AnalysisCache(home: home, directory: cacheDirectory), classifier = DeletionClassifier(home: home)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let leaf = deep.appendingPathComponent("payload.bin")
        try Data(repeating: 1, count: 32_768).write(to: leaf)
        try Data(repeating: 2, count: 8192).write(to: b.appendingPathComponent("stable.bin"))
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); print("PASS: \(message)")
        }
        func wait(_ condition: () -> Bool, seconds: Double = 10) {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(condition(), "Background operation finishes within its deadline")
        }
        var measured: [String] = []
        let measure: ExplorerSnapshotBuilder.Measure = { url, token, count in
            measured.append(url.lastPathComponent)
            return DiskScanner.measure(url, cancellation: token, counted: count)
        }
        func refresh(_ previous: CachedExplorerFolder?, changes: FolderChanges = FolderChanges(), force: Bool = false) throws -> CachedExplorerFolder {
            try ExplorerSnapshotBuilder.refresh(folder: data, previous: previous, changes: changes, force: force,
                checkpoint: FolderChangeMonitor.eventID(), cancellation: ScanCancellation(), classifier: classifier, measure: measure)
        }
        let original = try refresh(nil)
        check(Set(measured) == ["A", "B"], "First measurement walks both subtrees")
        cache.saveFolder(original)
        check(cache.loadFolder(data)?.totalBytes == original.totalBytes, "Folder measurements survive a new cache instance")
        let permissions = try fm.attributesOfItem(atPath: cacheDirectory.path)[.posixPermissions] as! NSNumber
        check(permissions.intValue == 0o700, "Persisted paths live in a private directory")
        measured = []
        _ = try refresh(original)
        check(measured.isEmpty, "Unchanged folders reuse all recursive measurements")
        let oldDirectory = DiskScanner.metadata(a).map(DiskScanner.fingerprint)
        try Data(repeating: 3, count: 262_144).write(to: leaf)
        check(DiskScanner.metadata(a).map(DiskScanner.fingerprint) == oldDirectory, "Deep edits leave the top folder timestamp unchanged")
        measured = []
        let incremental = try refresh(original, changes: FolderChanges(paths: [leaf.path]))
        check(measured == ["A"], "A deep edit measures only the changed branch")
        check(incremental.totalBytes == DiskScanner.measure(data, cancellation: ScanCancellation()).bytes,
              "Incremental totals match a complete inode-deduplicated measurement")
        measured = []
        _ = try refresh(incremental, changes: FolderChanges(full: true))
        check(Set(measured) == ["A", "B"], "Lost event history forces a complete measurement")
        let linked = b.appendingPathComponent("shared.bin")
        try fm.linkItem(at: leaf, to: linked)
        measured = []
        let hardLinks = try refresh(incremental, changes: FolderChanges(paths: [linked.path]))
        check(!hardLinks.independent && hardLinks.totalBytes == DiskScanner.measure(data, cancellation: ScanCancellation()).bytes,
              "New cross-folder hard links trigger a full walk without double counting")
        try fm.removeItem(at: linked)
        let baseline = try refresh(nil)
        cache.saveFolder(baseline)
        // Simulate changes while the application is closed, then replay macOS history.
        try Data(repeating: 4, count: 524_288).write(to: leaf)
        let explorer = FileExplorerModel(folder: data, home: home, cache: cache)
        var displayedPrevious = false
        let observer = explorer.$entries.sink { entries in
            if entries.first(where: { $0.url.path == a.path })?.measurement == baseline.entries.first(where: { $0.url.path == a.path })?.measurement {
                displayedPrevious = true
            }
        }
        explorer.loadIfNeeded()
        let changedTotal = DiskScanner.measure(data, cancellation: ScanCancellation()).bytes
        wait { !explorer.isScanning && explorer.totalBytes == changedTotal }
        check(displayedPrevious && explorer.error == nil && explorer.measuredAt != nil,
              "Cold entry displays saved rows before refreshing")
        check(explorer.totalBytes == DiskScanner.measure(data, cancellation: ScanCancellation()).bytes,
              "Reopening catches edits made while no event monitor was running")
        try Data(repeating: 5, count: 1_048_576).write(to: leaf)
        wait {
            let current = explorer.entries.first(where: { $0.url.path == a.path })?.measurement?.bytes ?? 0
            return !explorer.isScanning && current >= 1_048_576
        }
        check(explorer.totalBytes == DiskScanner.measure(data, cancellation: ScanCancellation()).bytes,
              "The visible Explorer responds to live deep-file events")
        let settledDate = explorer.measuredAt
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        check(!explorer.isScanning && explorer.measuredAt == settledDate, "Saving the cache does not create a scan feedback loop")
        explorer.suspendMonitoring(); observer.cancel()
        var corrupt = baseline
        corrupt.entries.append(baseline.entries[0]); cache.saveFolder(corrupt)
        check(cache.loadFolder(data) == nil, "Malformed duplicate cached rows are discarded")
        let wrongSchema = CachedExplorerFolder(schema: 999, folder: data, date: baseline.date, eventID: baseline.eventID,
            volumeID: baseline.volumeID, rootFingerprint: baseline.rootFingerprint, entries: baseline.entries,
            totalBytes: baseline.totalBytes, independent: true)
        cache.saveFolder(wrongSchema)
        check(cache.loadFolder(data) == nil, "Unknown cache schemas fall back to scanning")
        let scan = StorageIndexer.scan(roots: [data], home: home, cancellation: ScanCancellation(), limit: 2)
        cache.saveAnalysis(CachedStorageAnalysis(schema: 1, index: scan, duplicates: DuplicateReport(), snapshots: [], snapshotStatus: "test"))
        let restored = AnalysisCache(home: home, directory: cacheDirectory).loadAnalysis(home: home)
        check(restored?.index.allocated == scan.allocated && restored?.index.byPath == scan.byPath,
              "Smart Scan restores aggregates and rebuilds derived lookups for bounded detail")
        cache.invalidateAnalysis()
        check(cache.loadAnalysis(home: home) == nil, "Mutations invalidate the saved Smart Scan")
        let token = ScanCancellation(); token.cancel()
        do {
            _ = try ExplorerSnapshotBuilder.refresh(folder: data, previous: nil, changes: FolderChanges(full: true), force: true,
                checkpoint: 0, cancellation: token, classifier: classifier)
            preconditionFailure("Cancelled work must not produce a savable snapshot")
        } catch { print("PASS: Cancelled work cannot persist an incomplete scan") }
        print("Analysis cache tests passed with temporary data only.")
    }
}
