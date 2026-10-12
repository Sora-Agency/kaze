import Foundation
import AppKit
import Darwin

enum CleanupAuthorization {
    static func rule(for url: URL, home: URL, catalog: RuleCatalog, processes: String) -> CleanupRule? {
        guard pathIsWithin(url.path, root: home.path), url.path != home.path,
              canonicalFilePath(url) == url.path, !AnalysisProtection.isProtected(url, home: home),
              let s = DiskScanner.metadata(url), (s.st_mode & S_IFMT) == S_IFDIR,
              (s.st_flags & UInt32(SF_DATALESS)) == 0 else { return nil }
        let relative = String(url.path.dropFirst(home.path.count + 1))
        guard let rule = catalog.manifest.rules.first(where: { $0.regenerable && $0.paths.contains(relative) }),
              !rule.closedProcesses.contains(where: { processes.localizedCaseInsensitiveContains($0) }) else { return nil }
        return rule
    }
}
