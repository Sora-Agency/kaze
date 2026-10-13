import Foundation
import Darwin

struct ReviewedTrashService {
    let home: URL
    var catalog: RuleCatalog?
    var runningProcesses: () -> (output: String, status: Int32) = {
        CleanerOperations.runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
    }
    var move: (URL) throws -> URL? = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }

    func prepare(_ target: TrashTarget) throws -> ReviewedTrashRequest {
        let catalog = try verifiedCatalog()
        try checkLocation(target.url, catalog: catalog)
        let info = try metadata(target)
        let fingerprint = StorageIndexer.fingerprint(info)
        if let expected = target.fingerprint, fingerprint != expected { throw AnalysisActionError.changed }
        return ReviewedTrashRequest(target: target, fingerprint: fingerprint)
    }

    func perform(_ request: ReviewedTrashRequest, journal: OperationJournal, cancellation: ScanCancellation) throws {
        guard !cancellation.isCancelled else { throw ReviewedTrashError.cancelled }
        let catalog = try verifiedCatalog()
        let target = request.target
        try journal.trash(target.url, title: "Borrado manual", ruleVersion: catalog.manifest.version, preflight: {
            try checkLocation(target.url, catalog: catalog)
            let current = try metadata(target)
            guard StorageIndexer.fingerprint(current) == request.fingerprint else { throw AnalysisActionError.changed }
            let rule = matchingRule(target.url, catalog: catalog)
            if rule != nil || target.url.pathExtension.lowercased() == "app" {
                let processes = runningProcesses()
                guard processes.status == 0 else { throw AnalysisActionError.changed }
                let active = rule?.closedProcesses.filter { processes.output.localizedCaseInsensitiveContains($0) } ?? []
                guard active.isEmpty else { throw AnalysisActionError.inUse(active) }
                if target.url.pathExtension.lowercased() == "app",
                   processes.output.split(separator: "\n").contains(where: { pathIsWithin(String($0).trimmingCharacters(in: .whitespaces), root: target.url.path) }) {
                    throw AnalysisActionError.inUse([target.url.lastPathComponent])
                }
            }
            if target.directory {
                let tree = StorageIndexer.scan(roots: [target.url], home: home, cancellation: cancellation, limit: 1)
                guard !cancellation.isCancelled else { throw ReviewedTrashError.cancelled }
                guard !tree.partial, let root = tree.files.first, !root.containsProtected else { throw ReviewedTrashError.protectedItem }
            }
            guard !cancellation.isCancelled else { throw ReviewedTrashError.cancelled }
            guard let after = DiskScanner.metadata(target.url), StorageIndexer.fingerprint(after) == request.fingerprint else {
                throw AnalysisActionError.changed
            }
        }, move: move)
    }

    private func verifiedCatalog() throws -> RuleCatalog {
        let result = try catalog ?? RuleCatalog.bundled()
        try result.authorizeNative("trash")
        return result
    }

    private func metadata(_ target: TrashTarget) throws -> stat {
        guard target.url.isFileURL, canonicalFilePath(target.url) == target.url.path,
              let info = DiskScanner.metadata(target.url),
              (info.st_mode & S_IFMT) == (target.directory ? S_IFDIR : S_IFREG),
              (info.st_flags & UInt32(SF_DATALESS)) == 0 else { throw AnalysisActionError.changed }
        return info
    }

    private func checkLocation(_ url: URL, catalog: RuleCatalog) throws {
        let roots = ["/", "/Users", "/Volumes", home.path]
        guard !roots.contains(url.path), !AnalysisProtection.isProtected(url, home: home),
              !["framework", "kext", "dylib"].contains(url.pathExtension.lowercased()) else { throw ReviewedTrashError.protectedItem }
        if url.deletingLastPathComponent().path == "/Volumes" { throw ReviewedTrashError.protectedItem }
        if url.pathExtension.lowercased() == "app",
           pathIsWithin(url.path, root: "/Applications") || (pathIsWithin(url.path, root: home.path)
            && DeletionClassifier(home: home).assess(url.deletingLastPathComponent()).safety == .review) { return }
        let assessment = DeletionClassifier(home: home).assess(url)
        if assessment.safety != .review {
            guard pathIsWithin(url.path, root: home.path), matchingRule(url, catalog: catalog)?.regenerable == true else {
                throw ReviewedTrashError.protectedItem
            }
        }
    }

    private func matchingRule(_ url: URL, catalog: RuleCatalog) -> CleanupRule? {
        guard pathIsWithin(url.path, root: home.path) else { return nil }
        if let rule = catalog.manifest.rules.first(where: { rule in
            rule.paths.contains { pathIsWithin(url.path, root: home.appendingPathComponent($0).path) }
        }) { return rule }
        var ancestor = url
        while ancestor.path != home.path && pathIsWithin(ancestor.path, root: home.path) {
            if let rule = catalog.manifest.rules.first(where: { rule in
                rule.projectFolder == ancestor.lastPathComponent && (rule.manifests ?? []).contains { name in
                    guard let info = DiskScanner.metadata(ancestor.deletingLastPathComponent().appendingPathComponent(name)) else { return false }
                    return (info.st_mode & S_IFMT) == S_IFREG
                }
            }) { return rule }
            ancestor.deleteLastPathComponent()
        }
        return nil
    }
}
