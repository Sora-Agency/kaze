import Foundation

struct OperationRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    var originalPath: String
    var destinationPath: String?
    var fingerprint: FileFingerprint?
    var status: String
    var allocatedBytes: Int64?
    var freedBytes: Int64?
    var sourceDevice: Int64? = nil
    var observedFreeDelta: Int64? = nil
    var detail: String
    var ruleVersion: Int?
    var restorable: Bool { status == "trashed" && destinationPath != nil && (sourceDevice == nil || sourceDevice == fingerprint?.device) }
}
