import Foundation

struct APFSEntry: Codable, Sendable {
    let name: String
    let id: UInt64
    let parent: UInt64
    let kind: String
    let size: UInt64
}

struct RecoveryVolume: Identifiable, Hashable, Sendable {
    let id: UInt64
    let name: String
}

struct RecoveryDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    var rawPath: String { "/dev/r" + id }
}

struct RecoveryOutcome: Sendable {
    let folder: URL
    let files: Int
    let bytes: UInt64
    let failures: Int
    let damagedRecords: Int
    let cancelled: Bool
}
