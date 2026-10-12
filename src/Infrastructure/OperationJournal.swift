import Foundation
import Darwin
import Combine

final class OperationJournal: @unchecked Sendable {
    static let shared = OperationJournal(home: FileManager.default.homeDirectoryForCurrentUser)
    let directory: URL
    private let lock = NSRecursiveLock()
    private let leaseURL: URL
    private let broadcasts: Bool
    init(home: URL, leaseURL: URL = URL(fileURLWithPath: "/tmp/com.soraagency.kaze.lock")) {
        directory = URL(fileURLWithPath: canonicalFilePath(home), isDirectory: true).appendingPathComponent("Library/Application Support/Kaze/Operations")
        self.leaseURL = leaseURL
        broadcasts = canonicalFilePath(home) == canonicalFilePath(FileManager.default.homeDirectoryForCurrentUser)
    }

    func write(_ record: OperationRecord) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard canonicalFilePath(directory) == directory.path else { throw CocoaError(.fileWriteNoPermission) }
        let destination = directory.appendingPathComponent(record.id.uuidString + ".json")
        let data = try JSONEncoder().encode(record)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        NotificationCenter.default.post(name: .kazeOperationsChanged, object: nil)
        if broadcasts {
            DistributedNotificationCenter.default().postNotificationName(.kazeOperationsChanged,
                object: AppIdentity.bundleIdentifier, userInfo: nil, deliverImmediately: true)
        }
    }

    func records(limit: Int = 500) throws -> [OperationRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let latest = urls.filter { $0.pathExtension == "json" }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.prefix(limit)
        // Individual immutable IDs allow concurrent scheduled writers without a shared JSON append file.
        return latest.compactMap { url in
            guard let s = DiskScanner.metadata(url), (s.st_mode & S_IFMT) == S_IFREG, s.st_size < 1_048_576,
                  let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(OperationRecord.self, from: data) else { return nil }
            return record
        }.sorted { $0.date > $1.date }.prefix(limit).map { $0 }
    }

    func begin(url: URL, title: String, bytes: Int64? = nil, ruleVersion: Int? = nil) throws -> OperationRecord {
        let record = OperationRecord(id: UUID(), date: Date(), title: title, originalPath: url.path,
            status: "pending", allocatedBytes: bytes, freedBytes: nil, detail: "", ruleVersion: ruleVersion)
        try write(record)
        return record
    }

    func trash(_ url: URL, title: String, bytes: Int64? = nil, ruleVersion: Int? = nil,
               preflight: () throws -> Void = {},
               move: (URL) throws -> URL?) throws {
        lock.lock(); defer { lock.unlock() }
        let lease = try MutationLease(url: leaseURL); defer { withExtendedLifetime(lease) {} }
        guard let before = DiskScanner.metadata(url) else { throw CocoaError(.fileNoSuchFile) }
        var record = try begin(url: url, title: title, bytes: bytes ?? ((before.st_mode & S_IFMT) == S_IFDIR ? nil : Int64(before.st_blocks) * 512), ruleVersion: ruleVersion)
        record.originalPath = URL(fileURLWithPath: canonicalFilePath(url.deletingLastPathComponent()), isDirectory: true).appendingPathComponent(url.lastPathComponent).path
        record.sourceDevice = Int64(before.st_dev)
        do {
            try preflight()
            record.destinationPath = try move(url)?.path
            if let path = record.destinationPath, let s = DiskScanner.metadata(URL(fileURLWithPath: path)) {
                record.fingerprint = StorageIndexer.fingerprint(s)
                record.freedBytes = before.st_dev == s.st_dev ? 0 : nil
            }
            record.status = "trashed"
            // Moving to Trash frees no bytes. A free-space delta is not attributed to this operation.
            record.detail = record.freedBytes == 0 ? "Papelera: el espacio se libera cuando se vacía y APFS deja de conservarlo." : "Papelera: capacidad no verificable o traslado entre volúmenes; puede requerir restauración manual en Finder."
            try write(record)
        } catch {
            if let issue = error as? AnalysisActionError, case .pendingTrash = issue { record.status = "pending" }
            else { record.status = record.destinationPath == nil ? "failed" : "trashed" }
            record.detail = error.localizedDescription
            try? write(record)
            throw error
        }
    }

    func restore(_ supplied: OperationRecord) throws {
        lock.lock(); defer { lock.unlock() }
        let lease = try MutationLease(url: leaseURL); defer { withExtendedLifetime(lease) {} }
        // Re-read the persisted record; callers cannot supply arbitrary move instructions.
        let data = try Data(contentsOf: directory.appendingPathComponent(supplied.id.uuidString + ".json"))
        var record = try JSONDecoder().decode(OperationRecord.self, from: data)
        guard record.restorable, let destination = record.destinationPath, let fingerprint = record.fingerprint,
              let s = DiskScanner.metadata(URL(fileURLWithPath: destination)), StorageIndexer.fingerprint(s) == fingerprint else {
            throw CocoaError(.fileNoSuchFile)
        }
        let original = URL(fileURLWithPath: record.originalPath)
        guard DiskScanner.metadata(original) == nil,
              canonicalFilePath(original.deletingLastPathComponent()) == original.deletingLastPathComponent().path,
              FileManager.default.fileExists(atPath: original.deletingLastPathComponent().path) else { throw CocoaError(.fileWriteFileExists) }
        record.status = "restoring"; try write(record)
        do {
            guard renameatx_np(AT_FDCWD, destination, AT_FDCWD, original.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            record.status = "restored"; record.detail = "Restaurado en su ubicación original."; try write(record)
        } catch { record.status = "trashed"; record.detail = error.localizedDescription; try? write(record); throw error }
    }

    func external(title: String, target: String, bytes: Int64, status: Int32, detail: String) {
        let record = OperationRecord(id: UUID(), date: Date(), title: title, originalPath: target,
            status: status == 0 ? "completed" : "failed", allocatedBytes: bytes, freedBytes: nil,
            detail: detail, ruleVersion: nil)
        try? write(record)
    }
}

extension Notification.Name {
    static let kazeOperationsChanged = Notification.Name("kaze.operationsChanged")
    static let showKazeSection = Notification.Name("kaze.showSection")
}

enum OperationEvents {
    static var updates: AnyPublisher<Notification, Never> {
        let local = NotificationCenter.default.publisher(for: .kazeOperationsChanged)
        #if KAZE_PREVIEW
        return local.eraseToAnyPublisher()
        #else
        return local.merge(with: DistributedNotificationCenter.default().publisher(for: .kazeOperationsChanged, object: AppIdentity.bundleIdentifier as NSString)).eraseToAnyPublisher()
        #endif
    }
}
