import Foundation
import Darwin

protocol RecoveryFileReading: AnyObject {
    var volumeName: String { get }
    var volumes: [RecoveryVolume] { get }
    var damagedRecords: Int { get }
    func list(_ path: String) throws -> [APFSEntry]
    func recoverFile(_ path: String, to destination: URL) throws -> UInt64
}
extension APFSReader: RecoveryFileReading {}

final class RecoveryService: @unchecked Sendable {
    private var reader: RecoveryFileReading?
    private var descriptor: Int32 = -1
    private(set) var source: RecoverySource?
    private let discovery: RecoveryDiskDiscovery
    init(discovery: RecoveryDiskDiscovery = RecoveryDiskDiscovery()) { self.discovery = discovery }
    deinit { if descriptor >= 0 { close(descriptor) } }
    func disconnect() { reader = nil; source = nil; if descriptor >= 0 { close(descriptor) }; descriptor = -1 }
    func connect(_ source: RecoverySource, volumeID: UInt64? = nil, cancellation: OperationCancellation) throws -> RecoveryFileReading {
        disconnect()
        try discovery.verifyExternal(source, cancellation: cancellation)
        let fd = try source.openReadOnly(cancellation: cancellation)
        do {
            let disk = try APFSReader(fd: fd, base: source.offset, cancellation: cancellation, volumeID: volumeID)
            reader = disk; descriptor = fd; self.source = source
            return disk
        } catch { close(fd); throw error }
    }
    func list(_ path: String) throws -> [APFSEntry] {
        guard let reader else { throw APFSError.invalid("Abre el origen primero.") }
        return try reader.list(path)
    }
    var damagedRecords: Int { reader?.damagedRecords ?? 0 }
    func recover(_ paths: [String], in destination: URL, cancellation: OperationCancellation,
                 progress: (Int, UInt64) -> Void) throws -> RecoveryOutcome {
        guard let reader, let source else { throw APFSError.invalid("Abre el origen primero.") }
        try discovery.validateDestination(destination, source: source, cancellation: cancellation)
        return try RecoveryCopyOperation(reader: reader).run(paths, in: destination, cancellation: cancellation, progress: progress)
    }
}
