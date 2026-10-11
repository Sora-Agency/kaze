import Foundation
import AppKit

extension CleanerOperations {
    nonisolated static func discoverApplications(home: URL) -> [InstalledApplication] {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var seen = Set<String>()
        var result: [InstalledApplication] = []

        for root in roots {
            guard let entries = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension.lowercased() == "app" {
                let standardized = url.standardizedFileURL.path
                guard !seen.contains(standardized),
                      !AppIdentity.ownedBundleIdentifiers.contains(Bundle(url: url)?.bundleIdentifier ?? "") else { continue }
                seen.insert(standardized)

                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let identifier = bundle?.bundleIdentifier
                let related = relatedDataURLs(for: displayName, bundleIdentifier: identifier, home: home)
                let appSize = diskUsage(of: url)
                let relatedData = related.map { url in
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    return ApplicationDataItem(
                        id: url.standardizedFileURL.path,
                        applicationID: standardized,
                        url: url,
                        bytes: diskUsage(of: url),
                        isDirectory: values?.isDirectory == true && values?.isSymbolicLink != true
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

    nonisolated static func relatedDataURLs(for name: String, bundleIdentifier: String?, home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library")
        var candidates: [URL] = []

        if let identifier = bundleIdentifier, !identifier.isEmpty {
            candidates += [
                library.appendingPathComponent("Caches/\(identifier)"),
                library.appendingPathComponent("Containers/\(identifier)"),
                library.appendingPathComponent("HTTPStorages/\(identifier)"),
                library.appendingPathComponent("WebKit/\(identifier)"),
                library.appendingPathComponent("Preferences/\(identifier).plist"),
                library.appendingPathComponent("Saved Application State/\(identifier).savedState")
            ]
        }

        candidates.append(library.appendingPathComponent("Application Support/\(name)"))

        let known: [String: [String]] = [
            "docker": [
                "Library/Containers/com.docker.docker",
                "Library/Group Containers/group.com.docker",
                "Library/Application Support/Docker Desktop",
                "Library/Application Support/com.docker.install",
                ".docker"
            ],
            "google chrome": [
                "Library/Application Support/Google/Chrome",
                "Library/Caches/Google/Chrome"
            ],
            "steam": ["Library/Application Support/Steam"],
            "discord": ["Library/Application Support/discord"],
            "spotify": ["Library/Application Support/Spotify"],
            "postman": ["Library/Application Support/Postman"],
            "figma": ["Library/Application Support/Figma"],
            "antigravity": ["Library/Application Support/Antigravity"],
            "antigravity ide": ["Library/Application Support/Antigravity IDE"],
            "blender": ["Library/Application Support/Blender"],
            "beekeeper studio": ["Library/Application Support/beekeeper-studio"],
            "microsoft teams": [
                "Library/Containers/com.microsoft.teams2",
                "Library/Containers/com.microsoft.teams2.agent"
            ],
            "microsoft outlook": ["Library/Containers/com.microsoft.Outlook"],
            "whatsapp": ["Library/Containers/net.whatsapp.WhatsApp"]
        ]

        for relativePath in known[name.lowercased()] ?? [] {
            candidates.append(home.appendingPathComponent(relativePath))
        }

        var unique = Set<String>()
        return candidates
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .filter { unique.insert($0.path).inserted }
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
                isDirectory: isDirectory
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
