import Foundation
import Darwin

struct AssistantChatStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("conversations.json") }
    static let byteLimit = 8 * 1024 * 1024

    init(directory: URL) { self.directory = directory }
    init(home: URL) {
        directory = URL(fileURLWithPath: canonicalFilePath(home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Kaze/Chats", isDirectory: true)
    }

    func load() throws -> AssistantChatArchive {
        guard DiskScanner.metadata(directory) != nil else { return AssistantChatArchive() }
        try verifyDirectory()
        guard let info = DiskScanner.metadata(file) else { return AssistantChatArchive() }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, info.st_size <= Self.byteLimit,
              canonicalFilePath(file) == file.path else { throw CocoaError(.fileReadNoPermission) }
        let archive = try JSONDecoder().decode(AssistantChatArchive.self, from: Data(contentsOf: file))
        guard archive.version == 1, Set(archive.chats.map(\.id)).count == archive.chats.count,
              archive.chats.allSatisfy({ Set($0.turns.map(\.id)).count == $0.turns.count }) else { throw CocoaError(.fileReadCorruptFile) }
        return archive.bounded(interrupted: true)
    }

    func save(_ supplied: AssistantChatArchive) throws {
        let manager = FileManager.default
        guard canonicalFilePath(directory.deletingLastPathComponent()) == directory.deletingLastPathComponent().path else { throw CocoaError(.fileWriteNoPermission) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try verifyDirectory()
        if let info = DiskScanner.metadata(file) {
            guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, canonicalFilePath(file) == file.path else { throw CocoaError(.fileWriteNoPermission) }
        }
        let archive = supplied.bounded()
        let data = try JSONEncoder().encode(archive)
        guard data.count <= Self.byteLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        let temporary = directory.appendingPathComponent(".\(UUID()).json")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func verifyDirectory() throws {
        guard let info = DiskScanner.metadata(directory), (info.st_mode & S_IFMT) == S_IFDIR,
              canonicalFilePath(directory) == directory.path else { throw CocoaError(.fileWriteNoPermission) }
    }
}
