import Foundation
import Darwin

enum StorageIndexer {
    static func fingerprint(_ s: stat) -> FileFingerprint {
        FileFingerprint(device: Int64(s.st_dev), inode: UInt64(s.st_ino), size: Int64(s.st_size),
                        modified: Int64(s.st_mtimespec.tv_sec), nanoseconds: Int64(s.st_mtimespec.tv_nsec),
                        changed: Int64(s.st_ctimespec.tv_sec), changedNanoseconds: Int64(s.st_ctimespec.tv_nsec))
    }

    // Stream all metadata; retain bounded detail. Aggregates include files not retained in the map.
    static func scan(roots: [URL], home: URL, cancellation: ScanCancellation,
                     limit: Int = 250_000, progress: (Int) -> Void = { _ in }) -> StorageIndex {
        let home = URL(fileURLWithPath: canonicalFilePath(home), isDirectory: true)
        var seenRoots = Set<String>()
        let uniqueRoots = roots.map { URL(fileURLWithPath: canonicalFilePath($0), isDirectory: true) }.filter { seenRoots.insert($0.path).inserted }
        let roots = uniqueRoots.filter { root in !uniqueRoots.contains { $0 != root && pathIsWithin(root.path, root: $0.path) } }
        var index = StorageIndex(date: Date(), roots: roots, home: home, files: [], children: [:], byPath: [:])
        var identities = Set<DiskFileIdentity>()
        var directories = 0
        let manifests: Set<String> = ["package.json", "Podfile", "Package.swift", "build.gradle", "build.gradle.kts", "pyproject.toml", "requirements.txt"]
        let important: Set<String> = ["node_modules", "Pods", ".build", ".gradle", ".venv", "Caches", "DerivedData", "models", "store"]
        func account(_ url: URL, _ s: stat, parent: Int?, retain: Bool, blocked: Bool) -> Int? {
            index.scannedCount += 1
            let first = identities.insert(DiskFileIdentity(s)).inserted
            let directory = (s.st_mode & S_IFMT) == S_IFDIR
            let link = (s.st_mode & S_IFMT) == S_IFLNK
            let allocated = first ? max(0, Int64(s.st_blocks) * 512) : 0
            let logical = first && !directory ? max(0, Int64(s.st_size)) : 0
            let potential = first && !link && !blocked && (directory || s.st_nlink == 1) ? allocated : 0
            let kind = AnalysisProtection.systemKind(url, home: home)
            if let kind {
                index.systemTotals[kind, default: AnalysisBytes()].allocated += allocated
                index.systemTotals[kind, default: AnalysisBytes()].logical += logical
            }
            if index.scannedCount % 2048 == 0 { progress(index.scannedCount) }
            if retain {
                let position = index.files.count
                index.byPath[url.path] = position
                var file = IndexedFile(url: url, parent: parent, directory: directory, symbolicLink: link,
                    protected: blocked, fingerprint: fingerprint(s), links: UInt16(s.st_nlink), ownAllocated: allocated,
                    logical: logical, allocated: allocated, modified: Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec)))
                file.potentialAllocated = potential; file.containsProtected = blocked; file.systemKind = kind
                index.files.append(file)
                index.children[parent ?? -1, default: []].append(position)
                return position
            }
            index.omitted += 1
            if let parent {
                index.files[parent].allocated += allocated; index.files[parent].logical += logical
                index.files[parent].potentialAllocated += potential
                index.files[parent].containsProtected = index.files[parent].containsProtected || blocked
                index.files[parent].detailsLimited = true
            }
            return nil
        }
        for root in roots {
            if cancellation.isCancelled { index.cancelled = true; break }
            if index.byPath[root.path] != nil { continue }
            guard let s = DiskScanner.metadata(root), (s.st_mode & S_IFMT) == S_IFDIR else {
                index.unreadable += 1; continue
            }
            let blocked = AnalysisProtection.isProtected(root, home: home)
            let rootPosition = account(root, s, parent: nil, retain: true, blocked: blocked)!
            if AnalysisProtection.opaque(root, home: home) || (s.st_flags & UInt32(SF_DATALESS)) != 0 {
                index.unreadable += 1; index.files[rootPosition].partial = true; continue
            }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [],
                errorHandler: { _, _ in index.unreadable += 1; index.files[rootPosition].partial = true; return !cancellation.isCancelled }) else {
                index.unreadable += 1; index.files[rootPosition].partial = true; continue
            }
            var ancestors: [(nearest: Int, direct: Int?, blocked: Bool)] = [(rootPosition, rootPosition, blocked)]
            for case let url as URL in enumerator {
                if cancellation.isCancelled { index.cancelled = true; break }
                let depth = enumerator.level
                while ancestors.count > depth { ancestors.removeLast() }
                let parent = ancestors.last ?? (rootPosition, rootPosition, blocked)
                guard let metadata = DiskScanner.metadata(url) else {
                    index.unreadable += 1; index.files[parent.nearest].partial = true; enumerator.skipDescendants(); continue
                }
                guard metadata.st_dev == s.st_dev else {
                    index.unreadable += 1; index.files[parent.nearest].partial = true; enumerator.skipDescendants(); continue
                }
                let directory = (metadata.st_mode & S_IFMT) == S_IFDIR
                let protected = parent.blocked || AnalysisProtection.isProtected(url, home: home) || (metadata.st_flags & UInt32(SF_DATALESS)) != 0
                let retainDirectory = directory && (directories < min(50_000, max(1, limit / 4)) || depth <= 4 || important.contains(url.lastPathComponent))
                let retainFile = !directory && (!protected && AnalysisProtection.duplicateEligible(url, home: home) || manifests.contains(url.lastPathComponent))
                let retain = index.files.count < max(1, limit) && (retainDirectory || retainFile)
                if !retain && retainFile && !protected { index.candidateOmitted += 1 }
                let position = account(url, metadata, parent: parent.nearest, retain: retain, blocked: protected)
                if directory {
                    if retain { directories += 1 }
                    ancestors.append((position ?? parent.nearest, position, protected))
                    if AnalysisProtection.opaque(url, home: home) || (metadata.st_flags & UInt32(SF_DATALESS)) != 0
                        || pathIsWithin(url.path, root: home.appendingPathComponent("Library/Application Support/Kaze/Operations").path) {
                        index.unreadable += 1; index.files[position ?? parent.nearest].partial = true; enumerator.skipDescendants()
                    }
                }
            }
        }
        for position in index.files.indices.reversed() {
            if let parent = index.files[position].parent {
                index.files[parent].allocated += index.files[position].allocated
                index.files[parent].logical += index.files[position].logical
                index.files[parent].potentialAllocated += index.files[position].potentialAllocated
                index.files[parent].containsProtected = index.files[parent].containsProtected || index.files[position].containsProtected
                index.files[parent].partial = index.files[parent].partial || index.files[position].partial
                index.files[parent].detailsLimited = index.files[parent].detailsLimited || index.files[position].detailsLimited
            }
        }
        for i in index.files.indices where index.files[i].directory {
            guard let kind = index.files[i].systemKind else { continue }
            if let parent = index.files[i].parent, index.files[parent].systemKind == kind { continue }
            index.systemLocations[kind, default: []].append(i)
        }
        for kind in Array(index.systemLocations.keys) {
            index.systemLocations[kind] = Array(index.systemLocations[kind]!.sorted { index.files[$0].allocated > index.files[$1].allocated }.prefix(10))
        }
        if index.partial {
            for i in index.files.indices where index.files[i].parent == nil { index.files[i].partial = true }
            for key in Array(index.systemTotals.keys) { index.systemTotals[key]?.partial = true }
        }
        return index
    }
}
