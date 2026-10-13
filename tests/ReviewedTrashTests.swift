import Foundation

@main
struct ReviewedTrashTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); print("PASS: \(message)")
    }
    @MainActor static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(predicate(), "Background trash request completes")
    }
    @MainActor static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory)).appendingPathComponent("kaze-reviewed-trash-\(UUID())")
        let home = base.appendingPathComponent("Home"), trash = home.appendingPathComponent(".Trash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let catalog = try RuleCatalog(directory: URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src/Rules"))
        let journal = OperationJournal(home: home, leaseURL: base.appendingPathComponent("fixture.lock"))
        var moves = 0
        let service = ReviewedTrashService(home: home, catalog: catalog, runningProcesses: { ("", 0) }, move: { url in
            moves += 1
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try fm.moveItem(at: url, to: destination); return destination
        })
        func file(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url); return url
        }
        func reject(_ operation: () throws -> Void, _ message: String) {
            let before = moves
            do { try operation(); fatalError("Expected rejection: " + message) }
            catch { check(moves == before, message) }
        }

        let original = try file("Documents/personal.txt")
        let request = try service.prepare(TrashTarget(url: original, directory: false))
        try service.perform(request, journal: journal, cancellation: ScanCancellation())
        let record = try journal.records().first!
        check(!fm.fileExists(atPath: original.path) && record.restorable && record.freedBytes == 0,
              "Manual file trash is journaled without claiming freed disk capacity")
        try journal.restore(record)
        let restored = try Data(contentsOf: original)
        check(restored == Data("fixture".utf8), "History restores the complete file")

        let changed = try service.prepare(TrashTarget(url: original, directory: false))
        try Data("replacement content".utf8).write(to: original)
        reject({ try service.perform(changed, journal: journal, cancellation: ScanCancellation()) }, "Changed files are preserved after confirmation")
        let link = home.appendingPathComponent("Documents/link")
        try fm.createSymbolicLink(at: link, withDestinationURL: original)
        reject({ _ = try service.prepare(TrashTarget(url: link, directory: false)) }, "Symlinks never move their destination")
        reject({ _ = try service.prepare(TrashTarget(url: home, directory: true)) }, "Home cannot be moved")
        reject({ _ = try service.prepare(TrashTarget(url: URL(fileURLWithPath: "/System"), directory: true)) }, "System paths remain protected")
        let backup = try file("Documents/Backups/important.txt")
        let synced = try file("Library/CloudStorage/Provider/item.txt")
        let photo = try file("Pictures/Collection.photoslibrary/database")
        for url in [backup, synced, photo] {
            reject({ _ = try service.prepare(TrashTarget(url: url, directory: false)) }, "Backups, synchronized paths and Photos data remain protected")
        }

        _ = try file("Documents/Folder/nested/item.txt")
        let folder = home.appendingPathComponent("Documents/Folder")
        let folderRequest = try service.prepare(TrashTarget(url: folder, directory: true))
        _ = try file("Documents/Folder/nested/Backups/new.txt")
        reject({ try service.perform(folderRequest, journal: journal, cancellation: ScanCancellation()) }, "Fresh folder checks detect protected data added in a nested directory")
        let ordinary = try file("Documents/Archive/nested/keep.txt")
        let archive = ordinary.deletingLastPathComponent().deletingLastPathComponent()
        let model = ReviewedTrashModel(service: service, journal: journal)
        model.request(TrashTarget(url: archive, directory: true)); wait { !model.busy }
        check(model.pending != nil, "Folder selection prepares a confirmation without moving files")
        let before = moves
        model.confirm(contentsReviewed: false) { _ in fatalError("Missing folder acknowledgement") }
        check(moves == before && !model.busy && fm.fileExists(atPath: ordinary.path), "Folder removal requires explicit content review")
        var completed = false
        model.confirm(contentsReviewed: true) { url in completed = url == archive }
        wait { !model.busy }
        check(completed && model.lastMoved == archive && !fm.fileExists(atPath: archive.path), "Confirmed folder moves whole contents and reports success")
        let folderRecord = try journal.records().first { $0.originalPath == archive.path }!
        try journal.restore(folderRecord)
        check(fm.fileExists(atPath: ordinary.path), "History restores the entire folder and its nested files")

        let stopped = ScanCancellation(); stopped.cancel()
        let cancelled = try service.prepare(TrashTarget(url: ordinary, directory: false))
        reject({ try service.perform(cancelled, journal: journal, cancellation: stopped) }, "Cancellation prevents the trash move")
        model.request(TrashTarget(url: archive, directory: true)); wait { !model.busy }; model.dismiss()
        check(model.pending == nil && fm.fileExists(atPath: ordinary.path), "Dismissing confirmation preserves folder contents")

        let cache = try file("Library/Caches/com.google.Chrome/cache.bin")
        var active = service; active.runningProcesses = { ("Google Chrome", 0) }
        let cacheRequest = try active.prepare(TrashTarget(url: cache, directory: false))
        reject({ try active.perform(cacheRequest, journal: journal, cancellation: ScanCancellation()) }, "Known cache scopes still require their application to be closed")
        _ = try file("Projects/web/package.json")
        let dependency = try file("Projects/web/node_modules/tool/index.js")
        active.runningProcesses = { ("node", 0) }
        let dependencyRequest = try active.prepare(TrashTarget(url: dependency, directory: false))
        reject({ try active.perform(dependencyRequest, journal: journal, cancellation: ScanCancellation()) }, "Project descendants retain their signed closed-process requirements")
        let appFile = try file("Applications/Test.app/Contents/MacOS/Test")
        let app = appFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        active.runningProcesses = { (appFile.path, 0) }
        let appRequest = try active.prepare(TrashTarget(url: app, directory: true))
        reject({ try active.perform(appRequest, journal: journal, cancellation: ScanCancellation()) }, "Running apps are not moved by manual trash")
        let lease = try MutationLease(url: base.appendingPathComponent("fixture.lock"))
        reject({ try service.perform(cancelled, journal: journal, cancellation: ScanCancellation()) }, "Manual trash shares mutation exclusion with scheduled cleanup")
        withExtendedLifetime(lease) {}
    }
}
