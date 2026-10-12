import Foundation
import AppKit
import Darwin

extension CleanerOperations {
    nonisolated static func discoverApplications(home: URL, index: StorageIndex? = nil) -> [InstalledApplication] {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var seen = Set<String>()
        var result: [InstalledApplication] = []
        let appURLs = roots.flatMap { (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] }.filter { $0.pathExtension.lowercased() == "app" }
        var groupOwners: [String: [String]] = [:]
        var appGroups: [String: [String]] = [:]
        var identifierOwners: [String: [String]] = [:]
        for app in appURLs {
            if let id = Bundle(url: app)?.bundleIdentifier { identifierOwners[id.lowercased(), default: []].append(app.path) }
        }
        for app in appURLs { let groups = ApplicationAttribution.groups(app); appGroups[app.path] = groups; for group in groups { groupOwners[group, default: []].append(app.path) } }

        for root in roots {
            guard let entries = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension.lowercased() == "app" {
                let standardized = url.standardizedFileURL.path
                guard let metadata = DiskScanner.metadata(url), (metadata.st_mode & S_IFMT) == S_IFDIR, !seen.contains(standardized),
                      !AppIdentity.ownedBundleIdentifiers.contains(Bundle(url: url)?.bundleIdentifier ?? "") else { continue }
                seen.insert(standardized)

                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let identifier = bundle?.bundleIdentifier
                let related = ApplicationAttribution.discover(app: url, name: displayName, identifier: identifier, home: home, groupOwners: groupOwners, cachedGroups: appGroups[url.path], identifierOwners: identifierOwners)
                let appSize = index.flatMap { snapshot in snapshot.byPath[url.path].flatMap { snapshot.files[$0].partial ? nil : snapshot.files[$0].allocated } } ?? diskUsage(of: url)
                let relatedData = related.map { attributed in
                    let url = attributed.url
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    return ApplicationDataItem(
                        id: url.standardizedFileURL.path,
                        applicationID: standardized,
                        url: url,
                        bytes: index.flatMap { snapshot in snapshot.byPath[url.path].flatMap { snapshot.files[$0].partial ? nil : snapshot.files[$0].allocated } } ?? diskUsage(of: url),
                        isDirectory: values?.isDirectory == true && values?.isSymbolicLink != true,
                        evidence: attributed.evidence, sharedWith: attributed.sharedWith, verified: attributed.verified, requiresReview: attributed.url.path.contains("/Group Containers/") || attributed.url.path.contains("/LaunchAgents/")
                    )
                }

                result.append(InstalledApplication(
                    id: standardized,
                    name: displayName,
                    url: url,
                    bundleIdentifier: identifier,
                    appBytes: appSize,
                    relatedData: relatedData.sorted { $0.bytes > $1.bytes }
                ))
            }
        }

        return result
    }

    nonisolated static func discoverDirectoryChildren(
        of parent: ApplicationDataItem
    ) -> (items: [ApplicationDataItem], error: String?) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        let urls: [URL]
        do {
            urls = try manager.contentsOfDirectory(
                at: parent.url,
                includingPropertiesForKeys: keys,
                options: []
            )
        } catch {
            return ([], error.localizedDescription)
        }

        let usage = runCommand(
            "/usr/bin/du",
            arguments: ["-k", "-d", "1", parent.url.path],
            timeout: 18
        )
        var sizes: [String: Int64] = [:]
        for line in usage.output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kib = Int64(line[..<tab]) else { continue }
            let path = String(line[line.index(after: tab)...])
            sizes[URL(fileURLWithPath: path).standardizedFileURL.path] = kib * 1024
        }

        let items = urls.compactMap { url -> ApplicationDataItem? in
            let standardized = url.standardizedFileURL
            guard let values = try? standardized.resourceValues(forKeys: Set(keys)) else { return nil }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            let fallbackBytes = Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
            return ApplicationDataItem(
                id: standardized.path,
                applicationID: parent.applicationID,
                url: standardized,
                bytes: sizes[standardized.path] ?? fallbackBytes,
                isDirectory: isDirectory, evidence: parent.evidence, sharedWith: parent.sharedWith, verified: parent.verified, requiresReview: parent.requiresReview
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }

        let error = usage.status == 124
            ? L10n.text("El cálculo de tamaños agotó el tiempo; algunos valores pueden ser aproximados.")
            : nil
        return (items, error)
    }

}
