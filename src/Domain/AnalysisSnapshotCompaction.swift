import Foundation

enum AnalysisSnapshotCompaction {
    static func compact(_ value: CachedStorageAnalysis, limit: Int) -> CachedStorageAnalysis {
        var index = value.index
        let retained = index.files.indices.filter { $0 < limit || index.files[$0].parent == nil }
        let mapping = Dictionary(uniqueKeysWithValues: retained.enumerated().map { ($0.element, $0.offset) })
        index.files = retained.map { old in
            let file = value.index.files[old]
            var copy = IndexedFile(url: file.url, parent: file.parent.flatMap { mapping[$0] },
                directory: file.directory, symbolicLink: file.symbolicLink, protected: file.protected,
                fingerprint: file.fingerprint, links: file.links, ownAllocated: file.ownAllocated,
                logical: file.logical, allocated: file.allocated, potentialAllocated: file.potentialAllocated,
                modified: file.modified, partial: file.partial, containsProtected: file.containsProtected,
                detailsLimited: file.directory || file.detailsLimited, systemKind: file.systemKind)
            if file.parent != nil && copy.parent == nil { copy.partial = true }
            return copy
        }
        let omitted = value.index.files.count - retained.count
        index.omitted += omitted; index.candidateOmitted += omitted
        index.children = [:]; index.byPath = [:]
        index.systemLocations = index.systemLocations.mapValues { $0.compactMap { mapping[$0] } }
        var duplicates = value.duplicates
        func remap(_ group: DuplicateGroup) -> DuplicateGroup? {
            guard group.nodes.allSatisfy({ mapping[$0] != nil }) else { return nil }
            return DuplicateGroup(id: group.id, nodes: group.nodes.compactMap { mapping[$0] },
                                  similar: group.similar, potential: group.potential)
        }
        duplicates.exact = duplicates.exact.compactMap(remap)
        duplicates.similar = duplicates.similar.compactMap(remap)
        duplicates.partial = true; duplicates.skipped += omitted
        return CachedStorageAnalysis(schema: value.schema, index: index, duplicates: duplicates,
                                     snapshots: value.snapshots, snapshotStatus: value.snapshotStatus)
    }
}
