import Foundation

extension APFSReader {
    func records(in node: Data) throws -> (Bool, [APFSRecord]) {
        guard node.count == blockSize, Self.validChecksum(node) else {
            throw APFSError.invalid("Nodo APFS con checksum inválido")
        }
        let flags: UInt16 = try node.number(32)
        let count: UInt32 = try node.number(36)
        let tableOff: UInt16 = try node.number(40)
        let tableLen: UInt16 = try node.number(42)
        let fixed = flags & 4 != 0
        let leaf = flags & 2 != 0
        let tableStart = 56 + Int(tableOff)
        let keyStart = tableStart + Int(tableLen)
        let valueEnd = blockSize - (flags & 1 != 0 ? 40 : 0)
        let entrySize = fixed ? 4 : 8
        guard count <= 1000, tableStart + Int(count) * entrySize <= keyStart,
              keyStart < valueEnd else { throw APFSError.invalid("Tabla B-tree inválida") }
        var result: [APFSRecord] = []
        result.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let at = tableStart + index * entrySize
            let keyOffset: UInt16 = try node.number(at)
            let valOffset: UInt16 = try node.number(at + (fixed ? 2 : 4))
            if keyOffset == 0xffff || valOffset == 0xffff { continue }
            let keyLength: Int = fixed ? 16 : Int(try node.number(at + 2) as UInt16)
            let valLength: Int = fixed ? (leaf ? 16 : 8) : Int(try node.number(at + 6) as UInt16)
            let keyAt = keyStart + Int(keyOffset)
            let valAt = valueEnd - Int(valOffset)
            guard keyAt >= keyStart, keyAt + keyLength <= valueEnd,
                  valAt >= keyStart, valAt + valLength <= valueEnd else {
                throw APFSError.invalid("Entrada B-tree fuera del bloque")
            }
            result.append(APFSRecord(key: try node.bytes(keyAt, keyLength), value: try node.bytes(valAt, valLength)))
        }
        return (leaf, result)
    }

    func walk(root: UInt64, indirect: [UInt64: (UInt64, UInt64)]?, forgiving: Bool = false,
                      visit: (APFSRecord) throws -> Void) throws {
        var visited: Set<UInt64> = []
        func descend(_ oid: UInt64, depth: Int) throws {
            try cancellation.check()
            guard visited.count < 500_000 else { throw APFSError.invalid("El árbol APFS supera el límite de lectura") }
            guard depth < 12, !visited.contains(oid) else { throw APFSError.invalid("Ciclo o profundidad excesiva en B-tree") }
            visited.insert(oid)
            let physical: UInt64
            if let indirect {
                guard let entry = indirect[oid] else { throw APFSError.invalid("Nodo \(oid) ausente del mapa de objetos") }
                physical = entry.1
            } else { physical = oid }
            let (leaf, entries) = try records(in: readBlock(physical))
            if leaf {
                for record in entries {
                    do { try visit(record) }
                    catch {
                        if error is CancellationError || error is RecoveryLimitError { throw error }; if forgiving { damagedRecords += 1 } else { throw error }
                    }
                }
            } else {
                for record in entries {
                    do {
                        let child: UInt64 = try record.value.number(0)
                        try descend(child, depth: depth + 1)
                    } catch {
                        if error is CancellationError || error is RecoveryLimitError { throw error }; if forgiving { damagedRecords += 1 } else { throw error }
                    }
                }
            }
        }
        try descend(root, depth: 0)
    }

    func loadObjectMap(root: UInt64, indirect: [UInt64: (UInt64, UInt64)]?) throws -> [UInt64: (UInt64, UInt64)] {
        var map: [UInt64: (UInt64, UInt64)] = [:]
        try walk(root: root, indirect: indirect) { record in
            guard map.count < 500_000 else { throw APFSError.invalid("El mapa APFS supera el límite de lectura") }
            guard record.key.count >= 16, record.value.count >= 16 else { return }
            let oid: UInt64 = try record.key.number(0)
            let xid: UInt64 = try record.key.number(8)
            let flags: UInt32 = try record.value.number(0)
            let address: UInt64 = try record.value.number(8)
            if xid <= transaction, flags & 1 == 0, (map[oid]?.0 ?? 0) <= xid {
                map[oid] = (xid, address)
            }
        }
        return map
    }

}
