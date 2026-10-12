import Foundation
import CryptoKit

struct RuleCatalog {
    static let publicKey = "wiK0NIKqWP5QoRucK7FNYRj6Sh9cUsINdJwmewif7TM="
    let manifest: RuleManifest
    let digest: String

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("rules-v1.json"))
        let signatureText = try String(contentsOf: directory.appendingPathComponent("rules-v1.signature"), encoding: .utf8)
        guard let keyData = Data(base64Encoded: Self.publicKey), let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              try Curve25519.Signing.PublicKey(rawRepresentation: keyData).isValidSignature(signature, for: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try JSONDecoder().decode(RuleManifest.self, from: data)
        guard decoded.schema == 1, decoded.version == 1, Set(decoded.rules.map(\.id)).count == decoded.rules.count,
              decoded.rules.allSatisfy({ rule in
                  !rule.reason.isEmpty && !rule.recovery.isEmpty && !rule.closedProcesses.isEmpty
                  && rule.paths.allSatisfy { !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && !$0.isEmpty }
                  && (rule.projectFolder == nil || !(rule.manifests ?? []).isEmpty)
              }) else { throw CocoaError(.fileReadCorruptFile) }
        manifest = decoded
        digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func bundled() throws -> RuleCatalog {
        guard let resources = Bundle.main.resourceURL else { throw AnalysisActionError.rule }
        return try RuleCatalog(directory: resources.appendingPathComponent("Rules"))
    }

    func authorizeNative(_ action: String, processes: String? = nil) throws {
        guard let rule = manifest.rules.first(where: { $0.nativeAction == action }) else { throw AnalysisActionError.rule }
        if let processes {
            let running = rule.closedProcesses.filter { processes.localizedCaseInsensitiveContains($0) }
            guard running.isEmpty else { throw AnalysisActionError.inUse(running) }
        }
    }

    func matching(_ node: IndexedFile, index: StorageIndex, home: URL) -> CleanupRule? {
        guard !node.symbolicLink, !node.protected, node.directory,
              pathIsWithin(node.url.path, root: home.path), node.url.path != home.path else { return nil }
        let relative = String(node.url.path.dropFirst(home.path.count + 1))
        return manifest.rules.first { rule in
            if rule.paths.contains(relative) { return true }
            guard rule.projectFolder == node.url.lastPathComponent else { return false }
            let parent = node.url.deletingLastPathComponent()
            return (rule.manifests ?? []).contains { index.byPath[parent.appendingPathComponent($0).path] != nil }
        }
    }

    func findings(index: StorageIndex, home: URL) -> [StorageFinding] {
        var findings: [StorageFinding] = []
        var covered = Set<Int>()
        for (i, node) in index.files.enumerated() {
            if let parent = node.parent, covered.contains(parent) { covered.insert(i); continue }
            if let rule = matching(node, index: index, home: home) {
                findings.append(StorageFinding(node: i, group: rule.category == "development" ? .development : .safe,
                    rule: rule, potential: rule.regenerable && !node.partial && !node.containsProtected && rule.projectFolder == nil ? node.potentialAllocated : 0))
                covered.insert(i)
            } else if node.directory && node.url.pathExtension.lowercased() == "app" {
                findings.append(StorageFinding(node: i, group: .applications, rule: nil, potential: 0)); covered.insert(i)
            } else if !node.directory && node.allocated >= 100_000_000 {
                findings.append(StorageFinding(node: i, group: .review, rule: nil, potential: 0))
            }
        }
        return findings.sorted { index.files[$0.node].allocated > index.files[$1.node].allocated }
    }
}
