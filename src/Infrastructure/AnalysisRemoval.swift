import Foundation

/// Performs the journaled operation and fresh checks on the analysis utility queue.
/// Presentation state and selection remain in SmartScanModel.
enum AnalysisRemoval {
    static func trashSelection(nodes: Set<Int>, index: StorageIndex, findings: [StorageFinding],
                               groups: [DuplicateGroup], duplicatesOnly: Bool,
                               journal: OperationJournal, ruleVersion: Int,
                               runningProcesses: () -> (output: String, status: Int32) = {
                                   CleanerOperations.runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
                               },
                               move: (URL) throws -> URL? = { url in
                                   var destination: NSURL?
                                   try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
                                   return destination as URL?
                               }) -> [String] {
        var failures: [String] = []
        for node in nodes.sorted() {
            guard index.files.indices.contains(node) else { continue }
            let file = index.files[node]
            do {
                try journal.trash(file.url, title: duplicatesOnly ? "Duplicados exactos" : "Smart Scan", bytes: file.allocated, ruleVersion: ruleVersion, preflight: {
                    guard !file.protected, !file.symbolicLink, !file.partial, !file.containsProtected,
                          canonicalFilePath(file.url) == file.url.path,
                          let current = DiskScanner.metadata(file.url), StorageIndexer.fingerprint(current) == file.fingerprint else { throw AnalysisActionError.changed }
                    if duplicatesOnly {
                        guard DuplicateDetector.eligible(file, index: index),
                              let group = groups.first(where: { $0.nodes.dropFirst().contains(node) }),
                              let keeper = group.nodes.first,
                              DuplicateDetector.hash(index.files[keeper], cancellation: ScanCancellation()) == group.id,
                              DuplicateDetector.hash(file, cancellation: ScanCancellation()) == group.id else { throw AnalysisActionError.originalChanged }
                    } else {
                        guard let finding = findings.first(where: { $0.node == node }), let rule = finding.rule, rule.regenerable,
                              rule.projectFolder == nil else { throw AnalysisActionError.rule }
                        let processes = runningProcesses()
                        guard processes.status == 0 else { throw AnalysisActionError.changed }
                        let running = rule.closedProcesses.filter { processes.output.localizedCaseInsensitiveContains($0) }
                        guard running.isEmpty else { throw AnalysisActionError.inUse(running) }
                        // Recheck descendants so newly added backups, synced data or inaccessible files stay intact.
                        let currentTree = StorageIndexer.scan(roots: [file.url], home: index.home, cancellation: ScanCancellation(), limit: 1)
                        guard !currentTree.partial, let currentRoot = currentTree.files.first, !currentRoot.containsProtected,
                              let after = DiskScanner.metadata(file.url), StorageIndexer.fingerprint(after) == file.fingerprint else { throw AnalysisActionError.changed }
                    }
                }, move: move)
            } catch { failures.append(file.url.lastPathComponent + ": " + error.localizedDescription) }
        }
        return failures
    }
}
