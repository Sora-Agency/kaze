import Foundation

@main
struct AnalysisRemovalTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS: \(message)")
    }

    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory), isDirectory: true)
            .appendingPathComponent("kaze-removal-tests-\(UUID())")
        let home = root.appendingPathComponent("Home")
        let trash = home.appendingPathComponent(".Trash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let journal = OperationJournal(home: home, leaseURL: root.appendingPathComponent("fixture.lock"))
        let catalog = try RuleCatalog(directory: URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src/Rules"))
        func file(_ path: String, _ contents: String = "fixture content") throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
            return url
        }
        func scan(_ roots: [URL]) -> StorageIndex {
            StorageIndexer.scan(roots: roots, home: home, cancellation: ScanCancellation())
        }
        func move(_ url: URL) throws -> URL? {
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try fm.moveItem(at: url, to: destination)
            return destination
        }

        let original = try file("Documents/original.txt")
        let copy = try file("Documents/copy.txt")
        let index = scan([home.appendingPathComponent("Documents")])
        let keeper = index.byPath[original.path]!, duplicate = index.byPath[copy.path]!
        let hash = DuplicateDetector.hash(index.files[keeper], cancellation: ScanCancellation())!
        let group = DuplicateGroup(id: hash, nodes: [keeper, duplicate], similar: false, potential: 1)
        let failures = AnalysisRemoval.trashSelection(nodes: [duplicate], index: index, findings: [], groups: [group],
            duplicatesOnly: true, journal: journal, ruleVersion: catalog.manifest.version, move: move)
        check(failures.isEmpty && fm.fileExists(atPath: original.path) && !fm.fileExists(atPath: copy.path),
              "Duplicate removal keeps the verified original and moves only the selected copy")
        let records = try journal.records()
        check(records.count == 1 && records[0].status == "trashed" && records[0].freedBytes == 0,
              "Journal records the reversible move without claiming capacity was freed")

        let changedCopy = try file("Documents/second-copy.txt")
        let beforeChange = scan([home.appendingPathComponent("Documents")])
        let oldOriginal = beforeChange.byPath[original.path]!, secondCopy = beforeChange.byPath[changedCopy.path]!
        let changedGroup = DuplicateGroup(id: hash, nodes: [oldOriginal, secondCopy], similar: false, potential: 1)
        try Data("changed original content".utf8).write(to: original)
        var moveCalls = 0
        let rejected = AnalysisRemoval.trashSelection(nodes: [secondCopy], index: beforeChange, findings: [], groups: [changedGroup],
            duplicatesOnly: true, journal: journal, ruleVersion: 1, move: { _ in moveCalls += 1; return nil })
        check(rejected.count == 1 && moveCalls == 0 && fm.fileExists(atPath: changedCopy.path),
              "An original changed since hashing blocks duplicate deletion before the move")

        _ = try file("Library/Caches/com.google.Chrome/nested/cache.bin")
        let cache = home.appendingPathComponent("Library/Caches/com.google.Chrome")
        let cacheIndex = scan([cache])
        let findings = catalog.findings(index: cacheIndex, home: home)
        let node = cacheIndex.byPath[cache.path]!
        check(findings.contains { $0.node == node && $0.rule?.regenerable == true }, "Cache fixture uses a verified bundled scope")
        let inUse = AnalysisRemoval.trashSelection(nodes: [node], index: cacheIndex, findings: findings, groups: [],
            duplicatesOnly: false, journal: journal, ruleVersion: 1,
            runningProcesses: { ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", 0) },
            move: { _ in moveCalls += 1; return nil })
        check(inUse.count == 1 && moveCalls == 0, "A running required application blocks cache removal")
        _ = try file("Library/Caches/com.google.Chrome/nested/Backups/personal.txt")
        let protected = AnalysisRemoval.trashSelection(nodes: [node], index: cacheIndex, findings: findings, groups: [],
            duplicatesOnly: false, journal: journal, ruleVersion: 1, runningProcesses: { ("", 0) },
            move: { _ in moveCalls += 1; return nil })
        check(protected.count == 1 && moveCalls == 0 && fm.fileExists(atPath: cache.path),
              "Fresh descendant checks retain backups created inside a previously clean cache")
    }
}
