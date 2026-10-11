import Foundation
import Darwin

struct DiskFileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

enum DiskScanner {
    static func metadata(_ url: URL) -> stat? {
        var value = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path, lstat(path, &value) == 0 else { return nil }
            return value
        }
    }

    static func entries(at folder: URL, cancellation: ScanCancellation? = nil, classifier: DeletionClassifier = DeletionClassifier()) throws -> [FileEntry] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []).compactMap { url in
            guard cancellation?.isCancelled != true else { return nil }
            let info = metadata(url)
            let directory = info.map { ($0.st_mode & S_IFMT) == S_IFDIR } ?? false
            let link = info.map { ($0.st_mode & S_IFMT) == S_IFLNK } ?? false
            let modified = info.map { Date(timeIntervalSince1970: Double($0.st_mtimespec.tv_sec)) }
            let size = info.map { DiskMeasurement(bytes: Int64($0.st_blocks) * 512, fileCount: directory ? 0 : 1) }
                ?? DiskMeasurement(unreadableCount: 1)
            return FileEntry(url: url, isDirectory: directory, isSymbolicLink: link,
                             modified: modified, measurement: directory ? nil : size,
                             deletion: classifier.assess(url, isSymbolicLink: link, metadataAvailable: info != nil))
        }
    }

    static func measure(_ url: URL, cancellation: ScanCancellation,
                        progress: ((Int) -> Void)? = nil,
                        counted: ((stat) -> Void)? = nil) -> DiskMeasurement {
        var result = DiskMeasurement()
        var seen = Set<DiskFileIdentity>()
        func count(_ item: URL) {
            guard let info = metadata(item) else { result.unreadableCount += 1; return }
            let key = DiskFileIdentity(info)
            guard seen.insert(key).inserted else { return }
            result.bytes += Int64(info.st_blocks) * 512
            counted?(info)
            if (info.st_mode & S_IFMT) != S_IFDIR { result.fileCount += 1 }
        }
        guard !cancellation.isCancelled else { result.cancelled = true; return result }
        guard let root = metadata(url) else { result.unreadableCount = 1; return result }
        count(url)
        guard (root.st_mode & S_IFMT) == S_IFDIR else { return result }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
            options: [], errorHandler: { _, _ in result.unreadableCount += 1; return !cancellation.isCancelled }) else {
            result.unreadableCount += 1
            return result
        }
        var visited = 0
        for case let child as URL in enumerator {
            if cancellation.isCancelled { result.cancelled = true; break }
            count(child)
            visited += 1
            if visited % 2048 == 0 { progress?(visited) }
        }
        result.cancelled = cancellation.isCancelled
        return result
    }
}
