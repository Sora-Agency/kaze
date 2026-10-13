import Foundation

@main
struct CleanupCoverageTests {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); print("PASS: \(label)")
    }
    static func main() throws {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory), isDirectory: true)
            .appendingPathComponent("kaze-coverage-\(UUID())")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        func file(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("cache fixture".utf8).write(to: url); return url
        }
        let catalog = try RuleCatalog(directory: URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src/Rules"))
        _ = try file("Projects/confirmed/package.json")
        _ = try file("Projects/confirmed/node_modules/package/index.js")
        _ = try file("Projects/unknown/node_modules/custom.txt")
        let newRules = catalog.manifest.rules.filter { ["vscode-cache", "slack-cache", "yarn-cache"].contains($0.id) }
        for rule in newRules { for path in rule.paths { _ = try file(path + "/payload.bin") } }
        for path in ["Library/Application Support/Code/User/settings.json", "Library/Application Support/Code/Backups/document",
                     "Library/Application Support/Slack/Local Storage/session", "Projects/app/.yarn/cache/package"] { _ = try file(path) }
        let index = StorageIndexer.scan(roots: [home], home: home, cancellation: ScanCancellation())
        let findings = catalog.findings(index: index, home: home)
        check(findings.contains { $0.rule?.id == "node-modules" && $0.potential == 0 }
            && !findings.contains { index.files[$0.node].url.path == home.appendingPathComponent("Projects/unknown/node_modules").path },
              "Indexed matching still requires a project manifest and leaves dependencies for manual review")
        let projectSummary = CleanupOpportunitySummary.make(index: index, findings: findings, duplicates: .init())
        check(projectSummary.reviewBytes > 0 && projectSummary.allocatedByGroup[.development, default: 0] > 0,
              "Project dependencies appear as occupied review bytes instead of invented recovery")
        for rule in newRules {
            for path in rule.paths {
                let url = home.appendingPathComponent(path)
                check(findings.contains { $0.rule?.id == rule.id && index.files[$0.node].url == url && $0.potential > 0 },
                      "Signed scope detected and physically measured: \(path)")
                check(CleanupAuthorization.rule(for: url, home: home, catalog: catalog, processes: rule.closedProcesses[0]) == nil,
                      "Active app blocks expanded scope: \(path)")
                check(CleanupAuthorization.rule(for: url, home: home, catalog: catalog, processes: "") != nil,
                      "Closed app authorizes only its signed cache: \(path)")
            }
        }
        for path in ["Library/Application Support/Code", "Library/Application Support/Code/User",
                     "Library/Application Support/Slack", "Projects/app/.yarn/cache"] {
            check(CleanupAuthorization.rule(for: home.appendingPathComponent(path), home: home, catalog: catalog, processes: "") == nil,
                  "Profiles and project-local dependencies stay outside automatic scopes: \(path)")
        }
        let documents = home.appendingPathComponent("Documents")
        for n in 0..<100 { _ = try file("Documents/file-\(n)") }
        let code = home.appendingPathComponent("Library/Application Support/Code")
        let roots = [documents, code]
        let complete = StorageIndexer.scan(roots: roots, home: home, cancellation: ScanCancellation())
        let bounded = StorageIndexer.scan(roots: roots, home: home, cancellation: ScanCancellation(), limit: 12,
                                          priorityPaths: catalog.priorityPaths(home: home))
        check(bounded.files.count <= 12 && bounded.omitted > 0 && !bounded.partial, "Priority scopes keep the detail limit and complete metadata coverage")
        check(bounded.allocated == complete.allocated && bounded.logical == complete.logical && bounded.scannedCount == complete.scannedCount,
              "Reserving cache slots neither rescans nor loses allocated totals")
        check(catalog.findings(index: bounded, home: home).filter { $0.rule?.id == "vscode-cache" && $0.potential > 0 }.count == 4,
              "A late known cache survives an exhausted ordinary detail budget")
        let original = complete.byPath[documents.appendingPathComponent("file-0").path]!
        let copy = complete.byPath[documents.appendingPathComponent("file-1").path]!
        let cache = complete.byPath[code.appendingPathComponent("Cache").path]!
        let report = DuplicateReport(exact: [DuplicateGroup(id: "fixture", nodes: [original, copy], similar: false,
                                                          potential: complete.files[copy].allocated)])
        let summary = CleanupOpportunitySummary.make(index: complete, findings: [
            StorageFinding(node: original, group: .review, rule: nil, potential: 0),
            StorageFinding(node: copy, group: .review, rule: nil, potential: 0),
            StorageFinding(node: cache, group: .safe, rule: newRules[0], potential: complete.files[cache].potentialAllocated)
        ], duplicates: report)
        check(summary.reviewBytes == complete.files[original].allocated,
              "Review bytes exclude both verified caches and redundant exact copies")
        check(summary.potentialByGroup[.safe] == complete.files[cache].potentialAllocated,
              "Category recovery uses allocated candidates rather than logical file sizes")
    }
}
