import Foundation
import Darwin

final class FakeRecoveryReader: RecoveryFileReading {
    let volumeName = "Fixture"
    let volumes = [RecoveryVolume(id: 1, name: "Fixture")]
    let damagedRecords = 2
    var copied = 0
    var cancelAfterFirst: OperationCancellation?
    func list(_ path: String) throws -> [APFSEntry] {
        if path == "/" { return [APFSEntry(name: "folder", id: 2, parent: 1, kind: "dir", size: 0)] }
        return [APFSEntry(name: "good.txt", id: 3, parent: 2, kind: "file", size: 4),
                APFSEntry(name: "broken.txt", id: 4, parent: 2, kind: "file", size: 4),
                APFSEntry(name: "../escape", id: 5, parent: 2, kind: "file", size: 4),
                APFSEntry(name: "good.txt", id: 6, parent: 2, kind: "file", size: 4),
                APFSEntry(name: "loop", id: 2, parent: 2, kind: "dir", size: 0)]
    }
    func recoverFile(_ path: String, to destination: URL) throws -> UInt64 {
        try Data("safe".utf8).write(to: destination)
        if path.hasSuffix("broken.txt") { throw CocoaError(.fileReadCorruptFile) }
        copied += 1; cancelAfterFirst?.cancel(); return 4
    }
}
struct FakeDiskRunner: ToolCommandRunning {
    var destinationPhysical = "disk8s1"
    func run(_ executable: String, arguments: [String], cancellation: OperationCancellation) throws -> ToolCommandResult {
        let object: [String: Any]
        if arguments.first == "apfs" {
            object = ["Containers": [["ContainerReference": "disk9", "PhysicalStores": [["DeviceIdentifier": destinationPhysical]]]]]
        } else if arguments.last == "disk8s1" {
            object = ["Internal": false, "DeviceIdentifier": "disk8s1", "ParentWholeDisk": "disk8", "Content": "Apple_APFS"]
        } else { object = ["FilesystemType": "apfs", "ParentWholeDisk": "disk9"] }
        return ToolCommandResult(status: 0, data: try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0))
    }
}
@main struct RecoveryTests {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Kaze-Recovery-Test-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let reader = FakeRecoveryReader()
        let result = try RecoveryCopyOperation(reader: reader).run(["/folder"], in: root, cancellation: OperationCancellation()) { _, _ in }
        precondition(result.files == 1 && result.bytes == 4 && result.failures == 4 && result.damagedRecords == 2)
        let contents = try Data(contentsOf: result.folder.appendingPathComponent("folder/good.txt")); precondition(contents == Data("safe".utf8))
        precondition(!fm.fileExists(atPath: result.folder.appendingPathComponent("folder/broken.txt").path))
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("escape").path))
        precondition(fm.fileExists(atPath: result.folder.appendingPathComponent("recovery_report.txt").path))
        let token = OperationCancellation(); reader.cancelAfterFirst = token
        let stopped = try RecoveryCopyOperation(reader: reader).run(["/folder"], in: root, cancellation: token) { _, _ in }
        precondition(stopped.cancelled && stopped.files == 1)
        let source = try RecoverySource.device("/dev/rdisk8s1")
        precondition(source.physicalDisk == "disk8")
        for path in ["/dev/rdisk8s1/evil", "/dev/disk8s1", "/dev/rdisk8;echo", "/tmp/image"] {
            do { _ = try RecoverySource.device(path); fatalError("Invalid device accepted") } catch {}
        }
        let discovery = RecoveryDiskDiscovery(runner: FakeDiskRunner())
        try discovery.verifyExternal(source, cancellation: OperationCancellation())
        do { try discovery.validateDestination(root, source: source, cancellation: OperationCancellation()); fatalError("Same physical APFS disk accepted") } catch {}
        try RecoveryDiskDiscovery(runner: FakeDiskRunner(destinationPhysical: "disk7s2")).validateDestination(root, source: source, cancellation: OperationCancellation())
        do {
            try RecoveryDiskDiscovery(runner: FakeDiskRunner(destinationPhysical: "unknown")).validateDestination(root, source: source, cancellation: OperationCancellation())
            fatalError("Unknown physical store accepted")
        } catch {}
        let malformed = root.appendingPathComponent("invalid.img")
        try Data(repeating: 0, count: 4096).write(to: malformed)
        let fd = Darwin.open(malformed.path, O_RDONLY); defer { close(fd) }
        do { _ = try APFSReader(fd: fd, cancellation: OperationCancellation()); fatalError("Invalid APFS accepted") } catch {}
        precondition(!RecoveryCopyOperation.safeName("..") && !RecoveryCopyOperation.safeName("a\0b"))
        print("Recovery: copy, partial failure, collisions, traversal/cycles, cancellation, device validation and APFS physical stores passed")
    }
}
