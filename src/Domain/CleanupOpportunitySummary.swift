import Foundation

struct CleanupOpportunitySummary {
    var reviewBytes: Int64 = 0
    var allocatedByGroup: [FindingGroup: Int64] = [:]
    var potentialByGroup: [FindingGroup: Int64] = [:]

    static func make(index: StorageIndex, findings: [StorageFinding], duplicates: DuplicateReport) -> Self {
        var result = Self()
        let redundant = Set(duplicates.exact.flatMap { $0.nodes.dropFirst() })
        for finding in findings {
            let file = index.files[finding.node]
            result.allocatedByGroup[finding.group, default: 0] += file.allocated
            result.potentialByGroup[finding.group, default: 0] += finding.potential
            if finding.potential == 0 && !redundant.contains(finding.node) {
                result.reviewBytes += file.allocated
            }
        }
        return result
    }
}
