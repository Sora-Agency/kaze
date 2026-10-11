import Foundation
import Darwin

@main
struct ScannerTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("kaze-tests-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("blocked").path); try? manager.removeItem(at: root) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            print("PASS: \(message)")
        }
        let nested = root.appendingPathComponent("Nested.app/.hidden/deeper")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("payload\twith\nlines.bin")
        try Data(repeating: 0x5A, count: 131_072).write(to: file)
        try Data(repeating: 0x41, count: 8_192).write(to: root.appendingPathComponent(".hidden-file"))
        try manager.linkItem(at: file, to: nested.appendingPathComponent("hard-link"))
        try manager.createSymbolicLink(at: nested.appendingPathComponent("loop"), withDestinationURL: root)
        let sparse = root.appendingPathComponent("sparse.bin")
        manager.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 64 * 1024 * 1024); try handle.close()
        let entries = try DiskScanner.entries(at: root)
        check(entries.contains { $0.name == ".hidden-file" }, "Hidden files are listed")
        check(entries.first { $0.name == "Nested.app" }?.isDirectory == true, "Application bundles can be explored")
        check(entries.first { $0.name == "Nested.app" }?.measurement == nil, "Unmeasured folders are pending, not zero")
        let result = DiskScanner.measure(root, cancellation: ScanCancellation())
        check(!result.isPartial, "Nested folders and symlink loops finish without errors")
        check(result.fileCount == 4, "Hard links count once; symlink destination is not traversed")
        check(result.bytes < 1_000_000, "Sparse files use allocated bytes instead of logical size")
        let du = Process()
        let pipe = Pipe(); du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        du.arguments = ["-sk", root.path]; du.standardOutput = pipe
        try du.run(); du.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        let expected = Int64(output.split(separator: "\t")[0])! * 1024
        check(result.bytes == expected, "Recursive size matches macOS du including directory metadata")
        let cancelled = ScanCancellation(); cancelled.cancel()
        check(DiskScanner.measure(root, cancellation: cancelled).cancelled, "Cancellation stops a scan")
        check(DiskScanner.measure(root.appendingPathComponent("missing"), cancellation: ScanCancellation()).isPartial, "Missing or unreadable paths are explicitly partial")
        let blocked = root.appendingPathComponent("blocked")
        try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: blocked.appendingPathComponent("secret"))
        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        check(DiskScanner.measure(blocked, cancellation: ScanCancellation()).isPartial, "Permission errors never produce an apparently complete size")
        func entry(_ name: String, _ bytes: Int64?, _ seconds: Double, directory: Bool = false) -> FileEntry {
            FileEntry(url: root.appendingPathComponent(name), isDirectory: directory, isSymbolicLink: false,
                      modified: Date(timeIntervalSince1970: seconds), measurement: bytes.map { DiskMeasurement(bytes: $0) })
        }
        let a = entry("alpha.txt", 80, 100)
        let b = entry("beta.zip", 300, 200)
        let unknown = entry("aardvark", nil, 50, directory: true)
        check([a, b, unknown].sorted(by: FileOrder.largest.sorts).map(\.name) == ["beta.zip", "alpha.txt", "aardvark"], "Largest first includes folders and leaves pending sizes last")
        check([a, b, unknown].sorted(by: FileOrder.smallest.sorts).map(\.name) == ["alpha.txt", "beta.zip", "aardvark"], "Smallest first leaves pending sizes last")
        check([b, a].sorted(by: FileOrder.name.sorts).first?.name == a.name, "Alphabetical ascending")
        check([a, b].sorted(by: FileOrder.nameDescending.sorts).first?.name == b.name, "Alphabetical descending")
        check([a, b].sorted(by: FileOrder.newest.sorts).first?.name == b.name, "Newest first")
        check([b, a].sorted(by: FileOrder.oldest.sorts).first?.name == a.name, "Oldest first")
        check([b, a].sorted(by: FileOrder.type.sorts).first?.name == a.name, "Sort by file type")
        check(FileKindFilter.folders.includes(unknown) && !FileKindFilter.files.includes(unknown), "File and folder filters")
        print("All scanner tests passed.")
    }
}
