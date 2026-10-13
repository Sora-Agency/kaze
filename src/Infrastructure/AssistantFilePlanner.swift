import Foundation

enum AssistantFilePlanner {
    static func plan(index: StorageIndex, findings: [StorageFinding], question: String,
                     catalog: RuleCatalog?, cancellation: ScanCancellation) -> AssistantFilePlan {
        guard let catalog else { return AssistantFilePlan() }
        let service = ReviewedTrashService(home: index.home, catalog: catalog)
        let ranked = AssistantFileProposal.candidates(index: index, findings: findings, question: question,
            limit: 18, cancelled: { cancellation.isCancelled })
        var result = AssistantFilePlan()
        for proposal in ranked {
            guard !cancellation.isCancelled else { result.candidates = []; return result }
            result.checked += 1
            guard (try? service.prepare(proposal.target)) != nil else { result.skipped += 1; continue }
            result.candidates.append(proposal)
            if result.candidates.count == 6 { break }
        }
        return result
    }
}
