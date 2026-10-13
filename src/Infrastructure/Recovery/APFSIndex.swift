import Foundation

extension APFSReader {
    func parseInode(_ value: Data) throws -> APFSInode? {
        guard value.count >= 92 else { return nil }
        let streamID: UInt64 = try value.number(8)
        let mode: UInt16 = try value.number(80)
        var size: UInt64 = 0
        if value.count >= 96 {
            let count: UInt16 = try value.number(92)
            let header = 96
            var dataAt = header + Int(count) * 4
            if count < 64, dataAt <= value.count {
                for index in 0..<Int(count) {
                    let kind = value[header + index * 4]
                    let length: UInt16 = try value.number(header + index * 4 + 2)
                    if kind == 8, length >= 8 {
                        size = try value.number(dataAt)
                    }
                    dataAt += (Int(length) + 7) & ~7
                    if dataAt > value.count { break }
                }
            }
        }
        let flags: UInt64 = try value.number(48)
        return APFSInode(streamID: streamID, size: size, mode: mode, flags: flags)
    }

    func makeIndex() throws {
        if indexed { return }
        try walk(root: treeRoot, indirect: volumeMap, forgiving: true) { record in
            indexedRecords += 1
            guard indexedRecords <= 500_000 else { throw RecoveryLimitError() }
            guard record.key.count >= 8 else { return }
            let packed: UInt64 = try record.key.number(0)
            let oid = packed & 0x0fff_ffff_ffff_ffff
            let kind = packed >> 60
            switch kind {
            case 3:
                if let inode = try parseInode(record.value) { inodes[oid] = inode }
            case 8:
                guard record.key.count >= 16, record.value.count >= 16 else { return }
                let logical: UInt64 = try record.key.number(8)
                let rawLength: UInt64 = try record.value.number(0)
                let physical: UInt64 = try record.value.number(8)
                extents[oid, default: []].append(APFSExtent(logical: logical, length: rawLength & 0x00ff_ffff_ffff_ffff, physical: physical))
            case 4:
                guard record.key.count >= 11, record.value.count >= 4 else { return }
                let length: UInt16 = try record.key.number(8)
                if length > 0, 10 + Int(length) <= record.key.count {
                    let name = String(decoding: record.key[10..<(10 + Int(length))].prefix { $0 != 0 }, as: UTF8.self)
                    if name == "com.apple.decmpfs" {
                        let flags: UInt16 = try record.value.number(0)
                        let dataLength: UInt16 = try record.value.number(2)
                        if flags & 2 != 0, 4 + Int(dataLength) <= record.value.count {
                            compressionAttributes[oid] = try record.value.bytes(4, Int(dataLength))
                        }
                    } else if name == "com.apple.ResourceFork" {
                        let flags: UInt16 = try record.value.number(0)
                        let length: UInt16 = try record.value.number(2)
                        if flags & 1 != 0, length >= 48, record.value.count >= 52 {
                            let streamID: UInt64 = try record.value.number(4)
                            let size: UInt64 = try record.value.number(12)
                            resourceStreams[oid] = (streamID, size)
                        }
                    }
                }
            case 9:
                guard record.key.count >= 11, record.value.count >= 18 else { return }
                let start = hashedNames ? 12 : 10
                let count: Int
                if hashedNames {
                    let size: UInt32 = try record.key.number(8)
                    count = Int(size & 0x3ff)
                } else {
                    let size: UInt16 = try record.key.number(8)
                    count = Int(size)
                }
                guard count > 0, start + count <= record.key.count else { return }
                let name = String(decoding: record.key[start..<(start + count)].prefix { $0 != 0 }, as: UTF8.self)
                let id: UInt64 = try record.value.number(0)
                let flags: UInt16 = try record.value.number(16)
                let type = flags & 0x000f
                let kindName = type == 4 ? "dir" : type == 8 ? "file" : "other"
                directories[oid, default: []].append(APFSEntry(name: name, id: id, parent: oid, kind: kindName, size: 0))
            default: break
            }
        }
        for key in extents.keys { extents[key]?.sort { $0.logical < $1.logical } }
        indexed = true
    }

    func list(_ path: String) throws -> [APFSEntry] {
        try makeIndex()
        let id = try resolve(path)
        return (directories[id] ?? []).map { item in
            APFSEntry(name: item.name, id: item.id, parent: item.parent,
                      kind: item.kind, size: (try? compressionAttributes[item.id]?.number(8) as UInt64?) ?? inodes[item.id]?.size ?? 0)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func resolve(_ path: String) throws -> UInt64 {
        var current: UInt64 = 2
        for part in path.split(separator: "/") {
            guard let next = directories[current]?.first(where: { $0.name == String(part) }) else {
                throw APFSError.invalid("No se encontró \(path)")
            }
            current = next.id
        }
        return current
    }

}
