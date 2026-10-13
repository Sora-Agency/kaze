import Foundation

struct AssistantRecommendation: Identifiable {
    var id: String { rule.id }
    let rule: CleanupRule
    var count: Int
    var potential: Int64
    static func grouped(_ findings: [StorageFinding]) -> [AssistantRecommendation] {
        var groups: [String: AssistantRecommendation] = [:]
        for finding in findings {
            guard let rule = finding.rule else { continue }
            if groups[rule.id] == nil { groups[rule.id] = AssistantRecommendation(rule: rule, count: 0, potential: 0) }
            groups[rule.id]!.count += 1; groups[rule.id]!.potential += finding.potential
        }
        return groups.values.sorted {
            if $0.potential != $1.potential { return $0.potential > $1.potential }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }
    }
}
