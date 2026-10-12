// Adapted from LibreRescateNativo (MIT); see Recovery/LibreRescate-LICENSE.txt.
import Foundation
import Darwin

extension Data {
    func number<T: FixedWidthInteger>(_ offset: Int, as: T.Type = T.self) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw APFSError.invalid("Campo fuera de un bloque APFS")
        }
        return self.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }.littleEndian
    }
    func bytes(_ offset: Int, _ length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset + length <= count else {
            throw APFSError.invalid("Registro APFS fuera del bloque")
        }
        return subdata(in: offset..<(offset + length))
    }
}

struct APFSRecord {
    let key: Data
    let value: Data
}

struct APFSInode {
    let streamID: UInt64
    let size: UInt64
    let mode: UInt16
    let flags: UInt64
}

struct APFSExtent {
    let logical: UInt64
    let length: UInt64
    let physical: UInt64
}

/// Read-only APFS parser for the unencrypted volume in the attached disk.
/// Layout constants come from Apple's Apple File System Reference (2020).
final class APFSReader {
    let cancellation: OperationCancellation
    var indexedRecords = 0
    var volumes: [RecoveryVolume] = []
    let fd: Int32
    let base: UInt64
    let blockSize: Int
    let blockCount: UInt64
    var checkpoint = Data()
    var transaction: UInt64 = 0
    var containerMap: [UInt64: (UInt64, UInt64)] = [:]
    var volumeMap: [UInt64: (UInt64, UInt64)] = [:]
    var treeRoot: UInt64 = 0
    var directories: [UInt64: [APFSEntry]] = [:]
    var inodes: [UInt64: APFSInode] = [:]
    var extents: [UInt64: [APFSExtent]] = [:]
    var compressionAttributes: [UInt64: Data] = [:]
    var resourceStreams: [UInt64: (UInt64, UInt64)] = [:]
    var hashedNames = false
    var damagedRecords = 0
    var cache: [UInt64: Data] = [:]
    var indexed = false
    private(set) var volumeName = ""

    init(fd: Int32, base: UInt64 = 0, cancellation: OperationCancellation, volumeID: UInt64? = nil) throws {
        self.cancellation = cancellation
        self.fd = fd
        self.base = base
        let first = try Self.readExactly(fd: fd, offset: base, count: 4096)
        guard try first.bytes(32, 4) == Data("NXSB".utf8) else {
            throw APFSError.invalid("No hay una cabecera APFS en este dispositivo")
        }
        let size: UInt32 = try first.number(36)
        guard size == 4096 else { throw APFSError.invalid("Tamaño de bloque APFS no soportado: \(size)") }
        blockSize = Int(size)
        blockCount = try first.number(40)
        let descBlocks: UInt32 = try first.number(104)
        let descBase: UInt64 = try first.number(112)
        guard descBlocks > 0, descBlocks <= 65536, descBase < blockCount, UInt64(descBlocks) <= blockCount - descBase else {
            throw APFSError.invalid("Área de checkpoints inválida")
        }
        var best = first
        var bestXID: UInt64 = Self.validChecksum(first) ? try first.number(16) : 0
        for address in descBase..<(descBase + UInt64(descBlocks)) {
            try cancellation.check()
            guard let candidate = try? Self.readExactly(fd: fd, offset: try byteOffset(address), count: Int(size)),
                  (try? candidate.bytes(32, 4)) == Data("NXSB".utf8),
                  Self.validChecksum(candidate),
                  let xid: UInt64 = try? candidate.number(16), xid > bestXID else { continue }
            best = candidate
            bestXID = xid
        }
        guard Self.validChecksum(best) else { throw APFSError.invalid("No se encontró un checkpoint APFS válido") }
        checkpoint = best
        transaction = bestXID
        let containerOmap: UInt64 = try best.number(160)
        let omap = try readBlock(containerOmap)
        let omapTree: UInt64 = try omap.number(48)
        containerMap = try loadObjectMap(root: omapTree, indirect: nil)

        var selectedVolume: Data?
        for index in 0..<100 {
            let volumeOID: UInt64 = try best.number(184 + index * 8)
            if volumeOID == 0 { continue }
            guard let mapping = containerMap[volumeOID] else { continue }
            let volume = try readBlock(mapping.1)
            if Self.validChecksum(volume), (try? volume.bytes(32, 4)) == Data("APSB".utf8) {
                let rawName = try volume.bytes(704, 256)
                let name = String(decoding: rawName.prefix { $0 != 0 }, as: UTF8.self)
                volumes.append(RecoveryVolume(id: volumeOID, name: name))
                let flags: UInt64 = try volume.number(264)
                let incompatible: UInt64 = try volume.number(56)
                if volumeID == volumeOID || (volumeID == nil && selectedVolume == nil && flags & 1 != 0 && incompatible & 0x20 == 0) { selectedVolume = volume }
            }
        }
        guard let volume = selectedVolume else { throw APFSError.invalid("No se encontró un volumen APFS compatible sin cifrar") }
        let fsFlags: UInt64 = try volume.number(264)
        guard fsFlags & 1 != 0 else { throw APFSError.invalid("Los volúmenes cifrados aún no están soportados") }
        let incompatible: UInt64 = try volume.number(56)
        if incompatible & 0x20 != 0 { throw APFSError.invalid("Los volúmenes sellados aún no están soportados") }
        hashedNames = incompatible & 9 != 0
        let volumeOmap: UInt64 = try volume.number(128)
        treeRoot = try volume.number(136)
        let omapVolumeBlock = try readBlock(volumeOmap)
        let volumeOmapTree: UInt64 = try omapVolumeBlock.number(48)
        volumeMap = try loadObjectMap(root: volumeOmapTree, indirect: nil)
        let rawName = try volume.bytes(704, 256)
        volumeName = String(decoding: rawName.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func readExactly(fd: Int32, offset: UInt64, count: Int) throws -> Data {
        guard count >= 0, offset <= UInt64(Int64.max) - UInt64(count) else { throw APFSError.invalid("Dirección de lectura inválida") }
        var pointer: UnsafeMutableRawPointer?
        guard posix_memalign(&pointer, 4096, count) == 0, let pointer else {
            throw APFSError.invalid("No se pudo reservar memoria")
        }
        defer { free(pointer) }
        var received = 0
        while received < count {
            let got = pread(fd, pointer.advanced(by: received), count - received, off_t(offset) + off_t(received))
            if got < 0 && errno == EINTR { continue }
            guard got > 0 else { break }
            received += got
        }
        guard received == count else { throw APFSError.invalid("Falló la lectura en \(offset): \(String(cString: strerror(errno)))") }
        return Data(bytes: pointer, count: count)
    }

    static func validChecksum(_ data: Data) -> Bool {
        guard data.count >= 12, data.count % 4 == 0 else { return false }
        let modulus: UInt64 = 0xffff_ffff
        var a: UInt64 = 0
        var b: UInt64 = 0
        for offset in stride(from: 8, to: data.count, by: 4) {
            guard let word: UInt32 = try? data.number(offset) else { return false }
            a += UInt64(word)
            b += a
            if offset % 1024 == 0 { a %= modulus; b %= modulus }
        }
        a %= modulus
        b %= modulus
        let low = modulus - ((a + b) % modulus)
        let high = modulus - ((a + low) % modulus)
        guard let saved: UInt64 = try? data.number(0) else { return false }
        return saved == ((high << 32) | low)
    }

    func byteOffset(_ address: UInt64, extra: UInt64 = 0) throws -> UInt64 {
        let (bytes, multiplied) = address.multipliedReportingOverflow(by: UInt64(blockSize))
        let (offset, added) = base.addingReportingOverflow(bytes)
        let (result, advanced) = offset.addingReportingOverflow(extra)
        guard !multiplied, !added, !advanced, result <= UInt64(Int64.max) else {
            throw APFSError.invalid("Dirección de lectura inválida")
        }
        return result
    }

    func readBlock(_ address: UInt64) throws -> Data {
        try cancellation.check()
        guard address < blockCount else { throw APFSError.invalid("Bloque APFS fuera del contenedor: \(address)") }
        if let cached = cache[address] { return cached }
        let block = try Self.readExactly(fd: fd, offset: try byteOffset(address), count: blockSize)
        if cache.count >= 8192 { cache.removeAll(keepingCapacity: true) }
        cache[address] = block
        return block
    }

}
