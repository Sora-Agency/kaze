import Foundation
import CryptoKit

@main struct RecoveryImageTests {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Kaze-APFS-Fixture-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let runner = ToolCommandRunner(timeout: 60), token = OperationCancellation()
        func command(_ executable: String, _ arguments: [String]) throws -> Data {
            let result = try runner.run(executable, arguments: arguments, cancellation: token)
            guard result.status == 0 else { throw NSError(domain: "Fixture", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: String(decoding: result.data, as: UTF8.self)]) }
            return result.data
        }
        let image = root.appendingPathComponent("fixture.dmg"), mount = root.appendingPathComponent("mounted")
        _ = try command("/usr/bin/hdiutil", ["create", "-size", "96m", "-fs", "APFS", "-volname", "KazeFixture", "-layout", "NONE", image.path])
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let attached = try command("/usr/bin/hdiutil", ["attach", "-nobrowse", "-mountpoint", mount.path, "-plist", image.path])
        let plist = try PropertyListSerialization.propertyList(from: attached, format: nil) as! [String: Any]
        let entities = plist["system-entities"] as! [[String: Any]]
        let device = entities.compactMap { $0["dev-entry"] as? String }.first!
        var mounted = true
        defer { if mounted { _ = try? command("/usr/bin/hdiutil", ["detach", device]) } }
        let nested = mount.appendingPathComponent("folder/nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        try payload.write(to: nested.appendingPathComponent("payload.bin"))
        try Data("Fixture text".utf8).write(to: mount.appendingPathComponent("hello.txt"))
        try fm.createSymbolicLink(atPath: mount.appendingPathComponent("link").path, withDestinationPath: "hello.txt")
        _ = try command("/usr/bin/hdiutil", ["detach", device]); mounted = false
        let before = SHA256.hash(data: try Data(contentsOf: image))
        let service = RecoveryService()
        let source = RecoverySource(url: image, offset: 0, physicalDisk: nil)
        let reader = try service.connect(source, cancellation: token)
        precondition(reader.volumeName == "KazeFixture")
        let parser = reader as! APFSReader
        do { _ = try parser.decode(Data(), method: 3, expected: 32); fatalError("Empty compressed payload accepted") } catch {}
        do { _ = try APFSReader.readExactly(fd: parser.fd, offset: UInt64(Int64.max), count: 4096); fatalError("Overflowing read accepted") } catch {}
        let raw = try parser.decode(Data([0xff, 1, 2, 3]), method: 3, expected: 3)
        precondition(raw == Data([1, 2, 3]))
        let entries = try service.list("/")
        precondition(entries.contains { $0.name == "folder" && $0.kind == "dir" })
        let result = try service.recover(["/folder", "/hello.txt", "/link"], in: root, cancellation: token) { _, _ in }
        precondition(result.files == 2 && result.failures == 1 && result.bytes == UInt64(payload.count + 12))
        let recovered = try Data(contentsOf: result.folder.appendingPathComponent("folder/nested/payload.bin"))
        precondition(recovered == payload, "Recovered file differs from original")
        let volumeID = reader.volumes.first!.id
        _ = try service.connect(source, volumeID: volumeID, cancellation: token)
        let repeated = try service.list("/folder/nested")
        precondition(repeated.first?.name == "payload.bin")
        service.disconnect()
        let after = SHA256.hash(data: try Data(contentsOf: image))
        precondition(before == after, "Recovery wrote to its source")
        print("APFS image: native volume selection, recursive byte-for-byte recovery, unsupported symlink report and unchanged source hash passed")
    }
}
