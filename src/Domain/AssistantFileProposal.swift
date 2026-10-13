import Foundation

struct AssistantFileProposal: Identifiable {
    let id: String
    let file: IndexedFile
    let rule: CleanupRule?
    let potential: Int64
    let authorizationID = UUID()
    var target: TrashTarget { TrashTarget(file, authorizationID: authorizationID) }

    static func candidates(index: StorageIndex, findings: [StorageFinding], question: String,
                           limit: Int = 6, cancelled: () -> Bool = { false }) -> [Self] {
        guard AssistantQueryIntent.detect(question) == .fileActions else { return [] }
        let limit = min(24, max(1, limit))
        let words = question.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 3 }
        var result: [(finding: StorageFinding, relevance: Int)] = []
        for finding in findings {
            guard !cancelled() else { return [] }
            guard index.files.indices.contains(finding.node) else { continue }
            let file = index.files[finding.node]
            guard file.url.isFileURL, !file.symbolicLink, !file.protected, !file.containsProtected, !file.partial,
                  file.url.path != index.home.path, !index.roots.contains(file.url),
                  !AnalysisProtection.isProtected(file.url, home: index.home),
                  !result.contains(where: { index.files[$0.finding.node].id == file.id }) else { continue }
            if let rule = finding.rule {
                guard rule.regenerable, rule.nativeAction == nil, rule.commands == nil else { continue }
            } else {
                guard finding.group == .review, pathIsWithin(file.id, root: index.home.path),
                      !pathIsWithin(file.id, root: index.home.appendingPathComponent("Library").path),
                      !file.url.pathComponents.contains(where: { $0.hasPrefix(".") || ["app", "framework", "kext", "dylib"].contains(($0 as NSString).pathExtension.lowercased()) }) else { continue }
            }
            let label = file.url.path.lowercased() + " " + (finding.rule.map { L10n.string($0.title).lowercased() } ?? "")
            let relevance = words.reduce(0) { $0 + (label.contains($1) ? 1 : 0) }
            result.append((finding, relevance))
            result.sort {
                if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
                if $0.finding.potential != $1.finding.potential { return $0.finding.potential > $1.finding.potential }
                let left = index.files[$0.finding.node], right = index.files[$1.finding.node]
                if left.allocated != right.allocated { return left.allocated > right.allocated }
                return left.id < right.id
            }
            result = Array(result.prefix(limit))
        }
        return result.enumerated().map { offset, value in
            Self(id: "file_\(offset + 1)", file: index.files[value.finding.node], rule: value.finding.rule, potential: value.finding.potential)
        }
    }

}
