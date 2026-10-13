import Foundation
import Darwin

struct LocalAIStorage {
    let root: URL
    init(home: URL) {
        root = URL(fileURLWithPath: canonicalFilePath(home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Kaze/AI", isDirectory: true)
    }
    var exists: Bool { DiskScanner.metadata(root) != nil }
    func uninstall() throws {
        guard let info = DiskScanner.metadata(root) else { return }
        guard (info.st_mode & S_IFMT) == S_IFDIR, canonicalFilePath(root) == root.path else {
            throw LocalAIError.integrity
        }
        try FileManager.default.removeItem(at: root)
    }
}
