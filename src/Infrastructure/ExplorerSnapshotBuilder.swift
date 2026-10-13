import Foundation
import Darwin

enum ExplorerSnapshotBuilder {
    typealias Measure = (URL, ScanCancellation, @escaping (stat) -> Void) -> DiskMeasurement
    static func refresh(folder: URL, previous: CachedExplorerFolder?, changes: FolderChanges, force: Bool,
                        checkpoint: UInt64, cancellation: ScanCancellation, classifier: DeletionClassifier,
                        listed: ([FileEntry], Int64) -> Void = { _, _ in }, progress: (String) -> Void = { _ in },
                        checkpointed: (CachedExplorerFolder) -> Void = { _ in },
                        measure: Measure = { DiskScanner.measure($0, cancellation: $1, counted: $2) }) throws -> CachedExplorerFolder {
        let items = try DiskScanner.entries(at: folder, cancellation: cancellation, classifier: classifier)
        guard let root = DiskScanner.metadata(folder), (root.st_mode & S_IFMT) == S_IFDIR else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let old = Dictionary(uniqueKeysWithValues: (previous?.entries ?? []).map { ($0.url.path, $0) })
        let metadata = items.map { DiskScanner.metadata($0.url) }
        var visible = items
        for i in visible.indices where visible[i].isDirectory { visible[i].measurement = old[visible[i].url.path]?.measurement }
        var listedBytes = Int64(root.st_blocks) * 512, listedIdentities: Set<DiskFileIdentity> = [DiskFileIdentity(root)]
        for i in items.indices where !items[i].isDirectory {
            if let info = metadata[i], listedIdentities.insert(DiskFileIdentity(info)).inserted { listedBytes += Int64(info.st_blocks) * 512 }
        }
        listed(visible, previous?.totalBytes ?? listedBytes)
        let immediateChanged = previous?.entries.count != items.count || items.indices.contains {
            metadata[$0].map(DiskScanner.fingerprint) != old[items[$0].url.path]?.fingerprint
        } || previous?.rootFingerprint != DiskScanner.fingerprint(root)
        let full = force || previous == nil || changes.full
            || (previous?.independent == false && (immediateChanged || !changes.paths.isEmpty
                || previous?.entries.contains(where: { $0.measurement == nil }) == true))
        var total: Int64 = 0, independent = previous?.independent ?? true
        var seen = Set<DiskFileIdentity>()
        func count(_ info: stat) {
            if (info.st_mode & S_IFMT) != S_IFDIR && info.st_nlink > 1 { independent = false }
            if seen.insert(DiskFileIdentity(info)).inserted { total += Int64(info.st_blocks) * 512 }
        }
        if full { independent = true }
        count(root)
        let volumeID = FolderChangeMonitor.volumeID(Int64(root.st_dev))
        var partial = items.indices.map { i in
            var measurement = items[i].isDirectory ? old[items[i].url.path]?.measurement : items[i].measurement
            if items[i].isDirectory && (full || changes.affects(items[i].url)
                || metadata[i].map(DiskScanner.fingerprint) != old[items[i].url.path]?.fingerprint) { measurement?.cancelled = true }
            return CachedExplorerEntry(url: items[i].url, directory: items[i].isDirectory, symbolicLink: items[i].isSymbolicLink,
                modified: items[i].modified, fingerprint: metadata[i].map(DiskScanner.fingerprint),
                measurement: measurement)
        }
        func emitCheckpoint() {
            checkpointed(CachedExplorerFolder(schema: 1, folder: folder, date: Date(), eventID: checkpoint,
                volumeID: volumeID, rootFingerprint: DiskScanner.fingerprint(root),
                entries: partial, totalBytes: full ? total : previous?.totalBytes ?? total, independent: independent))
        }
        emitCheckpoint()
        var entries: [CachedExplorerEntry] = []
        for i in items.indices {
            guard !cancellation.isCancelled else { throw CocoaError(.userCancelled) }
            let item = items[i], fingerprint = metadata[i].map(DiskScanner.fingerprint)
            let saved = old[item.url.path]
            let dirty = full || changes.affects(item.url) || fingerprint != saved?.fingerprint
                || saved?.measurement == nil || saved?.measurement?.cancelled == true
            let measurement: DiskMeasurement?
            if item.isDirectory {
                if dirty { progress(item.name) }
                measurement = dirty ? measure(item.url, cancellation, { info in
                    if full { count(info) }
                    else if (info.st_mode & S_IFMT) != S_IFDIR && info.st_nlink > 1 { independent = false }
                }) : saved?.measurement
                if !full { total += measurement?.bytes ?? 0 }
            } else {
                measurement = item.measurement
                if let info = metadata[i] { count(info) }
            }
            entries.append(CachedExplorerEntry(url: item.url, directory: item.isDirectory, symbolicLink: item.isSymbolicLink,
                modified: item.modified, fingerprint: fingerprint, measurement: measurement))
            partial[i] = entries.last!; emitCheckpoint()
        }
        guard !cancellation.isCancelled else { throw CocoaError(.userCancelled) }
        if !full && !independent && (previous?.independent == true || immediateChanged || !changes.paths.isEmpty) {
            return try refresh(folder: folder, previous: previous, changes: changes, force: true,
                               checkpoint: checkpoint, cancellation: cancellation, classifier: classifier,
                               listed: listed, progress: progress, checkpointed: checkpointed, measure: measure)
        }
        if !full && !independent, let previous { total = previous.totalBytes }
        return CachedExplorerFolder(schema: 1, folder: folder, date: Date(), eventID: checkpoint,
            volumeID: FolderChangeMonitor.volumeID(Int64(root.st_dev)), rootFingerprint: DiskScanner.fingerprint(root),
            entries: entries, totalBytes: total, independent: independent)
    }
}
