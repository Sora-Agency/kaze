import Foundation
import CryptoKit
import Darwin

/// Local display metadata, never deletion authorization. All calls run on utility queues.
final class AnalysisCache: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private let fm = FileManager.default
    private let folderLimit = 8 * 1024 * 1024
    private let scanLimit = 96 * 1024 * 1024
    private let budget = 128 * 1024 * 1024
    init(home: URL, directory: URL? = nil) {
        self.directory = directory ?? home.appendingPathComponent("Library/Caches/Kaze/Analysis-v1", isDirectory: true)
    }
    private func folderURL(_ folder: URL) -> URL {
        let key = SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("folder-\(key).plist")
    }
    private func read<T: Decodable>(_ type: T.Type, at url: URL, limit: Int) -> T? {
        guard let info = DiskScanner.metadata(url), info.st_size > 0, info.st_size <= limit,
              (info.st_mode & S_IFMT) == S_IFREG, let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(type, from: data)
    }
    func loadFolder(_ folder: URL) -> CachedExplorerFolder? {
        lock.lock(); defer { lock.unlock() }
        guard let value = read(CachedExplorerFolder.self, at: folderURL(folder), limit: folderLimit), value.schema == 1,
              value.folder.path == folder.path, value.date <= Date().addingTimeInterval(60), value.totalBytes >= 0,
              value.entries.count <= 50_000, Set(value.entries.map { $0.url.path }).count == value.entries.count,
              value.entries.allSatisfy({ $0.url.isFileURL && $0.url.deletingLastPathComponent().path == folder.path
                  && ($0.measurement?.bytes ?? 0) >= 0 && ($0.measurement?.bytes ?? 0) <= Int64.max / 50_001
                  && ($0.measurement?.fileCount ?? 0) >= 0 && ($0.measurement?.unreadableCount ?? 0) >= 0 }) else { return nil }
        return value
    }
    func saveFolder(_ value: CachedExplorerFolder) {
        lock.lock(); defer { lock.unlock() }
        write(value, at: folderURL(value.folder), limit: folderLimit)
    }
    func loadAnalysis(home: URL) -> CachedStorageAnalysis? {
        lock.lock(); defer { lock.unlock() }
        guard var value = read(CachedStorageAnalysis.self, at: directory.appendingPathComponent("smart.plist"), limit: scanLimit),
              value.schema == 1, value.index.home.path == home.path, value.index.files.count <= 250_000,
              value.index.date <= Date().addingTimeInterval(60), value.index.roots.allSatisfy(\.isFileURL),
              value.index.unreadable >= 0, value.index.omitted >= 0, value.index.candidateOmitted >= 0,
              value.index.scannedCount >= value.index.files.count else { return nil }
        // Rebuild derived lookups; serialized offsets are not trusted.
        var index = value.index
        index.children = [:]; index.byPath = [:]
        let maximum = Int64.max / Int64(max(1, index.files.count))
        for (i, file) in index.files.enumerated() {
            guard file.url.isFileURL, file.allocated >= 0, file.allocated <= maximum, file.logical >= 0, file.logical <= maximum,
                  file.potentialAllocated >= 0, file.potentialAllocated <= maximum, file.ownAllocated >= 0,
                  file.ownAllocated <= maximum, index.byPath[file.url.path] == nil else { return nil }
            if let parent = file.parent {
                guard parent >= 0, parent < i, index.files[parent].directory,
                      file.url.path != index.files[parent].url.path,
                      pathIsWithin(file.url.path, root: index.files[parent].url.path) else { return nil }
            } else if !index.roots.contains(where: { $0.path == file.url.path }) { return nil }
            index.children[file.parent ?? -1, default: []].append(i); index.byPath[file.url.path] = i
        }
        let groups = value.duplicates.exact + value.duplicates.similar
        guard groups.count <= index.files.count,
              Set(value.duplicates.exact.flatMap(\.nodes)).count == value.duplicates.exact.flatMap(\.nodes).count,
              groups.allSatisfy({ group in
            group.id.count <= 128 && group.potential >= 0 && group.potential <= maximum && group.nodes.count >= 2
                && Set(group.nodes).count == group.nodes.count
                && group.nodes.allSatisfy { index.files.indices.contains($0) }
        }), index.systemTotals.values.allSatisfy({ $0.logical >= 0 && $0.allocated >= 0
            && $0.logical <= Int64.max / 100 && $0.allocated <= Int64.max / 100 }),
            index.systemLocations.values.allSatisfy({ $0.count <= 10 && $0.allSatisfy { index.files.indices.contains($0) } }) else { return nil }
        value = CachedStorageAnalysis(schema: 1, index: index, duplicates: value.duplicates,
                                      snapshots: value.snapshots, snapshotStatus: value.snapshotStatus)
        return value
    }
    func saveAnalysis(_ value: CachedStorageAnalysis) {
        lock.lock(); defer { lock.unlock() }
        write(value, at: directory.appendingPathComponent("smart.plist"), limit: scanLimit)
    }
    func invalidateAnalysis() {
        lock.lock(); defer { lock.unlock() }
        try? fm.removeItem(at: directory.appendingPathComponent("smart.plist"))
    }
    private func write<T: Encodable>(_ value: T, at url: URL, limit: Int) {
        do {
            if let info = DiskScanner.metadata(directory), (info.st_mode & S_IFMT) != S_IFDIR { return }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try encoder.encode(value)
            guard data.count <= limit else { return }
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            prune()
        } catch { /* Cache failure cannot prevent scans or replace visible results. */ }
    }
    private func prune() {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let values = files.filter { $0.pathExtension == "plist" }.compactMap { url -> (URL, Date, Int)? in
            guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var bytes = 0; var folders = 0
        for (url, _, size) in values {
            bytes += size
            if url.lastPathComponent.hasPrefix("folder-") { folders += 1 }
            if bytes > budget || folders > 32 { try? fm.removeItem(at: url) }
        }
    }
}
