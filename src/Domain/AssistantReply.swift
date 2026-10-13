import Foundation

struct AssistantReply {
    let answer: String
    let proposals: [AssistantFileProposal]

    static func schema(candidates: [AssistantFileProposal]) throws -> String {
        var item: [String: Any] = ["type": "string"]
        if !candidates.isEmpty { item["enum"] = candidates.map(\.id) }
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
            "required": ["answer", "proposals"], "properties": [
                "answer": ["type": "string", "minLength": 1, "maxLength": 1000],
                "proposals": ["type": "array", "items": item, "maxItems": min(3, candidates.count)]
            ]]
        return String(decoding: try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys), as: UTF8.self)
    }

    static func parse(_ raw: String, candidates: [AssistantFileProposal]) -> Self {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") {
            text = String(text.dropFirst(8).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard text.utf8.count <= 65_536, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["answer", "proposals"], let answer = object["answer"] as? String,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let ids = object["proposals"] as? [String], ids.count <= 3 else {
            return Self(answer: String(raw.prefix(8000)), proposals: [])
        }
        let allowed = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        guard ids.allSatisfy({ allowed[$0] != nil }) else { return Self(answer: answer, proposals: []) }
        var seen = Set<String>()
        let proposals = ids.compactMap { id -> AssistantFileProposal? in
            guard seen.insert(id).inserted, let proposal = allowed[id],
                  !seen.contains(where: { other in other != id && allowed[other].map { pathIsWithin(proposal.file.id, root: $0.file.id) } == true }) else { return nil }
            return proposal
        }
        return Self(answer: String(answer.prefix(8000)), proposals: proposals)
    }
}
