import Foundation
import CryptoKit
import Darwin

final class AnalysisCache: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private let fm = FileManager.default
    private let folderLimit = 8 * 1024 * 1024
    private let scanLimit: Int
    private let budget: Int
    private let legacy: URL?
    private var migrated = false
    init(home: URL, directory: URL? = nil, scanLimit: Int = 96 * 1024 * 1024, budget: Int = 128 * 1024 * 1024) {
        self.directory = directory ?? home.appendingPathComponent("Library/Application Support/Kaze/Analysis-v1", isDirectory: true)
        legacy = directory == nil ? home.appendingPathComponent("Library/Caches/Kaze/Analysis-v1", isDirectory: true) : nil
        self.scanLimit = scanLimit; self.budget = budget
    }
    private func migrate() {
        guard !migrated else { return }; migrated = true
        if let legacy { AnalysisCacheMigration.migrate(from: legacy, to: directory, budget: budget) }
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
        migrate()
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
        migrate()
        guard var value = read(CachedStorageAnalysis.self, at: directory.appendingPathComponent("smart.plist"), limit: scanLimit),
              value.schema == 1, value.index.home.path == home.path, value.index.files.count <= 250_000,
              value.index.date <= Date().addingTimeInterval(60), value.index.roots.allSatisfy(\.isFileURL),
              value.index.unreadable >= 0, value.index.omitted >= 0, value.index.candidateOmitted >= 0,
              value.index.scannedCount >= value.index.files.count else { return nil }
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
    @discardableResult func saveAnalysis(_ value: CachedStorageAnalysis) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        var candidate = value
        while let data = try? encoder.encode(candidate) {
            if data.count <= scanLimit { return write(data, at: directory.appendingPathComponent("smart.plist"), limit: scanLimit) }
            let count = candidate.index.files.count
            let next = max(0, Int(Double(count) * Double(scanLimit) / Double(data.count) * 0.8))
            candidate = AnalysisSnapshotCompaction.compact(candidate, limit: next)
            if candidate.index.files.count >= count { return false }
        }
        return false
    }
    func invalidateAnalysis() {
        lock.lock(); defer { lock.unlock() }
        try? fm.removeItem(at: directory.appendingPathComponent("smart.plist"))
    }
    @discardableResult private func write<T: Encodable>(_ value: T, at url: URL, limit: Int) -> Bool {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        guard let data = try? encoder.encode(value) else { return false }
        return write(data, at: url, limit: limit)
    }
    private func write(_ data: Data, at url: URL, limit: Int) -> Bool {
        do {
            guard data.count <= limit, canonicalFilePath(directory) == directory.path else { return false }
            if let info = DiskScanner.metadata(directory), (info.st_mode & S_IFMT) != S_IFDIR { return false }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            prune()
            return true
        } catch { return false }
    }
    private func prune() {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let values = files.filter { $0.lastPathComponent == "smart.plist"
            || $0.lastPathComponent.range(of: "^folder-[a-f0-9]{64}\\.plist$", options: .regularExpression) != nil }.compactMap { url -> (URL, Date, Int)? in
            guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var bytes = values.first { $0.0.lastPathComponent == "smart.plist" }?.2 ?? 0
        var folders = 0
        for (url, _, size) in values {
            if url.lastPathComponent == "smart.plist" { continue }
            bytes += size
            if url.lastPathComponent.hasPrefix("folder-") { folders += 1 }
            if bytes > budget || folders > 32 { try? fm.removeItem(at: url) }
        }
    }
}
