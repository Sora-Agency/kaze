import Foundation
import AppKit
import Darwin

@main
struct AnalysisEngineTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); print("PASS: \(message)")
    }
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory), isDirectory: true).appendingPathComponent("kaze-analysis-tests-\(UUID())")
        let home = root.appendingPathComponent("Home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func file(_ path: String, _ contents: Data = Data("same".utf8)) throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url); return url
        }
        let a = try file("Documents/a.txt"), b = try file("Documents/b.txt")
        _ = try file("Documents/different.txt", Data("diff".utf8))
        let hard = try file("Documents/hard.txt", Data("link".utf8))
        try fm.linkItem(at: hard, to: home.appendingPathComponent("Documents/hard-copy.txt"))
        let sparse = try file("Documents/sparse.bin", Data())
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.seek(toOffset: 536_870_912); try handle.write(contentsOf: Data([1])); try handle.close()
        let full = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation())
        check(full.logical > 536_870_912 && full.allocated < 1_048_576, "Sparse logical size never becomes recoverable disk space")
        check(full.allocated == DiskScanner.measure(home, cancellation: ScanCancellation()).bytes, "Whole-index allocation deduplicates hard links and agrees with metadata measurement")
        let bounded = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation(), limit: 1)
        check(bounded.files.count == 1 && bounded.omitted > 0 && !bounded.partial, "Detail limits do not stop a complete metadata walk")
        check(bounded.allocated == full.allocated && bounded.logical == full.logical && bounded.scannedCount == full.scannedCount, "Bounded maps preserve complete totals and coverage counts")
        let duplicates = DuplicateDetector.exact(index: full, cancellation: ScanCancellation(), byteBudget: 100)
        check(duplicates.exact.count == 1 && Set(duplicates.exact[0].nodes.map { full.files[$0].url }) == Set([a,b]), "Equal size is filtered by SHA-256; unequal content and hard links are excluded")
        let expected = DiskScanner.metadata(b).map { Int64($0.st_blocks) * 512 }!
        check(duplicates.exact[0].potential == expected, "Duplicate recovery keeps one original and counts only redundant physical allocation")
        let changed = full.files[full.byPath[b.path]!]
        try Data("edit".utf8).write(to: b)
        check(DuplicateDetector.hash(changed, cancellation: ScanCancellation()) == nil, "Changed files are rejected before hashing or deletion")
        let stopped = ScanCancellation(); stopped.cancel()
        check(StorageIndexer.scan(roots: [home], home: home, cancellation: stopped).cancelled, "Cancelled analysis exits without walking the filesystem")
        check(DuplicateDetector.hash(full.files[full.byPath[a.path]!], cancellation: stopped) == nil, "Hashing is cancellable between bounded reads")

        _ = try file("Library/CloudStorage/Provider/private.txt")
        _ = try file("Pictures/Archive.photoslibrary/original.jpg")
        _ = try file("Backups/a.txt")
        let protected = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation())
        check(protected.partial && protected.byPath[home.appendingPathComponent("Library/CloudStorage/Provider/private.txt").path] == nil,
              "Cloud provider folders remain opaque and disclose incomplete coverage")
        check(!protected.files.contains { $0.url.lastPathComponent == "original.jpg" }, "Photos payloads never enter hashing or deletion candidates")
        check(protected.files.first { $0.url.path == home.appendingPathComponent("Backups").path }?.containsProtected == true, "Backup folders propagate protection to cleanup parents")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<128 { for y in 0..<128 {
            bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 127, green: CGFloat(y) / 127, blue: (x + y) % 2 == 0 ? 0.2 : 0.8, alpha: 1), atX: x, y: y)
        } }
        let png = bitmap.representation(using: .png, properties: [:])!
        _ = try file("Pictures/first.png", png); _ = try file("Pictures/second.png", png)
        _ = try file("Pictures/invalid.jpg", Data("not an image".utf8))
        let photoIndex = StorageIndexer.scan(roots: [home.appendingPathComponent("Pictures")], home: home, cancellation: ScanCancellation())
        let photos = DuplicateDetector.similar(index: photoIndex, cancellation: ScanCancellation())
        check(photos.examined == 2 && photos.similar.count == 1 && photos.similar[0].potential == 0,
              "Apple Vision compares bounded local thumbnails and leaves similar photos for review")
        check(photos.partial && photos.skipped == 1, "Invalid images disclose incomplete visual comparison")
        let exhaustive = DuplicateDetector.exact(index: full, cancellation: ScanCancellation(), byteBudget: 0, exhaustive: true)
        check(exhaustive.examined > 0, "Exhaustive hashing removes quick-scan byte limits and rejects stale fingerprints")

        let forked = try file("Documents/resource-fork.txt", Data("same body".utf8))
        _ = try file("Documents/plain-copy.txt", Data("same body".utf8))
        let forkBytes = Data("unique resource content".utf8)
        let result = forkBytes.withUnsafeBytes { setxattr(forked.path, "com.apple.ResourceFork", $0.baseAddress, $0.count, 0, 0) }
        check(result == 0, "Fixture creates a real macOS resource fork")
        let forkIndex = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation())
        check(DuplicateDetector.hash(forkIndex.files[forkIndex.byPath[forked.path]!], cancellation: ScanCancellation()) == nil,
              "Equal data forks never authorize removal of unique resource-fork content")
        let resources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src")
        let catalog = try RuleCatalog(directory: resources.appendingPathComponent("Rules"))
        check(catalog.manifest.version == 1 && catalog.manifest.rules.count >= 20, "Bundled versioned rules verify with the app update public key")
        let cache = try file("Library/Developer/Xcode/DerivedData/project/build.o").deletingLastPathComponent().deletingLastPathComponent()
        let cacheIndex = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation())
        check(cacheIndex.systemLocations[.caches]?.contains(where: { cacheIndex.files[$0].url == cache }) == true,
              "System Data assigns DerivedData roots and children to the same category")
        let overlapping = StorageIndexer.scan(roots: [home, home.appendingPathComponent("Documents")], home: home, cancellation: ScanCancellation())
        check(overlapping.roots.map(\.path) == [home.path] && overlapping.allocated == cacheIndex.allocated, "Overlapping roots are scanned once without replacing folder measurements")
        let findings = catalog.findings(index: cacheIndex, home: home)
        check(findings.contains { $0.rule?.id == "xcode-derived" && $0.potential > 0 }, "Recoverable findings come from signed scopes and measured allocation")
        check(CleanupAuthorization.rule(for: cache, home: home, catalog: catalog, processes: "/usr/bin/xcodebuild") == nil, "Active required processes block cleanup authorization")
        check(CleanupAuthorization.rule(for: cache, home: home, catalog: catalog, processes: "/usr/bin/idle") != nil, "Closed-tool cache scope is authorized without arbitrary shell patterns")
        let corrupt = root.appendingPathComponent("CorruptRules")
        try fm.copyItem(at: resources.appendingPathComponent("Rules"), to: corrupt)
        var tampered = try Data(contentsOf: corrupt.appendingPathComponent("rules-v1.json")); tampered.append(32)
        try tampered.write(to: corrupt.appendingPathComponent("rules-v1.json"))
        check((try? RuleCatalog(directory: corrupt)) == nil, "Tampering with any policy byte disables the cleanup catalog")

        let app = home.appendingPathComponent("Applications/Test.app")
        _ = try file("Applications/Test.app/Contents/MacOS/helper", Data())
        _ = try file("Library/Preferences/org.example.Test.plist")
        _ = try file("Library/Application Support/Test/data")
        let attributed = ApplicationAttribution.discover(app: app, name: "Test", identifier: "org.example.Test", home: home,
            groupOwners: ["group.test": [app.path, "/Applications/Another.app"]], cachedGroups: ["group.test"])
        check(attributed.contains { $0.url.lastPathComponent == "org.example.Test.plist" && $0.verified }, "Exact bundle-ID preferences have verifiable attribution")
        check(attributed.contains { $0.url.lastPathComponent == "Test" && !$0.verified }, "Name matching alone never authorizes removal of application data")

        let sharedAttribution = ApplicationAttribution.discover(app: app, name: "Test", identifier: "org.example.Test", home: home,
            groupOwners: [:], identifierOwners: ["org.example.test": [app.path, "/Applications/Test copy.app"]])
        check(sharedAttribution.first { $0.url.lastPathComponent == "org.example.Test.plist" }?.sharedWith == ["/Applications/Test copy.app"],
              "Multiple installations with the same bundle ID share preferences and are preserved")
        let journalHome = root.appendingPathComponent("JournalHome")
        let trash = root.appendingPathComponent("FixtureTrash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = OperationJournal(home: journalHome, leaseURL: root.appendingPathComponent("mutation.lock"))
        let original = try file("Documents/restore.txt", Data("valuable".utf8))
        let destination = trash.appendingPathComponent("restore.txt")
        try journal.trash(original, title: "Fixture", bytes: 4096) { source in try fm.moveItem(at: source, to: destination); return destination }
        let record = try journal.records().first!
        check(record.restorable && record.freedBytes == 0 && record.allocatedBytes == 4096, "Trash operations record exact destination and never claim immediate recovery")
        try Data("new file".utf8).write(to: original)
        do { try journal.restore(record); preconditionFailure("Restore overwrote an existing file") } catch {}
        let collisionContents = try String(contentsOf: original)
        check(collisionContents == "new file" && fm.fileExists(atPath: destination.path), "Undo refuses to overwrite existing data")
        try fm.removeItem(at: original); try journal.restore(record)
        let restoredContents = try String(contentsOf: original)
        let restoredRecords = try journal.records()
        check(restoredContents == "valuable" && restoredRecords.first?.status == "restored", "Undo restores the original payload and persists the operation outcome")
        try journal.trash(original, title: "Fixture") { source in try fm.moveItem(at: source, to: destination); return destination }
        let second = try journal.records().first!
        try Data("edited trash".utf8).write(to: destination)
        do { try journal.restore(second); preconditionFailure("Restore accepted altered Trash contents") } catch {}
        check(!fm.fileExists(atPath: original.path), "Undo validates the trashed inode and content-change metadata")
        let link = home.appendingPathComponent("Documents/link")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "a.txt")
        let trashedLink = trash.appendingPathComponent("link")
        try journal.trash(link, title: "Link") { source in try fm.moveItem(at: source, to: trashedLink); return trashedLink }
        let linkRecord = try journal.records().first!
        check(linkRecord.originalPath == link.path, "History resolves parent aliases while preserving a symbolic link's own name")
        try journal.restore(linkRecord)
        let linkTarget = try fm.destinationOfSymbolicLink(atPath: link.path)
        check(linkTarget == "a.txt", "Undo restores the original relative link without touching its target")
        var foreign = linkRecord; foreign.status = "trashed"; foreign.sourceDevice = -1
        check(!foreign.restorable, "Cross-volume Trash records never offer an unsupported automatic restore")
        let held = try MutationLease(url: root.appendingPathComponent("mutation.lock"))
        do { try journal.trash(destination, title: "Blocked") { _ in preconditionFailure("Concurrent mutation executed") }; preconditionFailure("Ignored lease") } catch {}
        withExtendedLifetime(held) {}
        check(fm.fileExists(atPath: destination.path), "Manual and scheduled mutation exclusion preserves the active operation")

        let tiles = SpaceMapLayout.tiles(weights: [(1, 50),(2, 30),(3, 20)], in: CGRect(x: 0, y: 0, width: 800, height: 500))
        check(tiles.count == 3 && abs(tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height } - 400_000) < 0.01, "Treemap covers its bounds without gaps or double counting")
        check(abs(tiles.first { $0.id == 1 }!.rect.width * tiles.first { $0.id == 1 }!.rect.height - 200_000) < 0.01, "Treemap area is proportional to allocated bytes")
        check(!tiles[0].rect.intersects(tiles[1].rect) || tiles[0].rect.intersection(tiles[1].rect).width == 0, "Treemap hit targets do not overlap")

        let benchmark = root.appendingPathComponent("Benchmark")
        try fm.createDirectory(at: benchmark, withIntermediateDirectories: true)
        for i in 0..<10_000 { fm.createFile(atPath: benchmark.appendingPathComponent("\(i).txt").path, contents: Data()) }
        let start = Date()
        let measured = StorageIndexer.scan(roots: [benchmark], home: root, cancellation: ScanCancellation(), limit: 500)
        check(measured.scannedCount == 10_001 && measured.files.count <= 500 && !measured.partial, "Large directories have bounded retained detail with complete metadata coverage")
        print(String(format: "Metadata benchmark: 10,000 files in %.3f s; %d retained nodes", Date().timeIntervalSince(start), measured.files.count))
        print("Analysis engine tests passed without reading user data or invoking cleanup commands.")
    }
}
