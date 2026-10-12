import Foundation

struct CachedExplorerEntry: Codable {
    let url: URL
    let directory: Bool
    let symbolicLink: Bool
    let modified: Date?
    let fingerprint: FileFingerprint?
    let measurement: DiskMeasurement?

}

struct CachedExplorerFolder: Codable {
    let schema: Int
    let folder: URL
    var date: Date
    var eventID: UInt64
    let volumeID: String?
    let rootFingerprint: FileFingerprint
    var entries: [CachedExplorerEntry]
    let totalBytes: Int64
    /// Cross-child hard links require a complete walk to compute the parent total.
    let independent: Bool
    var complete: Bool { entries.allSatisfy { $0.measurement?.isPartial == false && $0.fingerprint != nil } }
}

struct CachedStorageAnalysis: Codable {
    let schema: Int
    let index: StorageIndex
    let duplicates: DuplicateReport
    let snapshots: [String]
    let snapshotStatus: String
}
