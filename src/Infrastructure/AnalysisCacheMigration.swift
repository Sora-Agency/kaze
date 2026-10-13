import Foundation
import Darwin

enum AnalysisCacheMigration {
    static func migrate(from legacy: URL, to directory: URL, budget: Int) {
        let fm = FileManager.default
        guard canonicalFilePath(legacy) == legacy.path, canonicalFilePath(directory) == directory.path,
              let urls = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let files = urls.filter { $0.lastPathComponent == "smart.plist"
            || $0.lastPathComponent.range(of: "^folder-[a-f0-9]{64}\\.plist$", options: .regularExpression) != nil }
            .sorted { a, b in
                if (a.lastPathComponent == "smart.plist") != (b.lastPathComponent == "smart.plist") { return a.lastPathComponent == "smart.plist" }
                return ((try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
        var bytes = 0
        for file in files {
            guard let info = DiskScanner.metadata(file), (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0,
                  info.st_size <= (file.lastPathComponent == "smart.plist" ? 96 : 8) * 1024 * 1024 else { continue }
            bytes += Int(info.st_size)
            guard bytes <= budget else { continue }
            let target = directory.appendingPathComponent(file.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try Data(contentsOf: file).write(to: target, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                try fm.removeItem(at: file)
            } catch { }
        }
    }
}
