// Adapted from LibreRescateNativo (MIT); see Recovery/LibreRescate-LICENSE.txt.
import Foundation

extension APFSReader {
    func recoverFile(_ path: String, to destination: URL) throws -> UInt64 {
        try makeIndex()
        let id = try resolve(path)
        guard let inode = inodes[id], inode.mode & 0xf000 == 0x8000 else {
            throw APFSError.invalid("La ruta no es un archivo regular")
        }
        let compressionType: UInt32? = try compressionAttributes[id].map { try $0.number(4) }
        if compressionType == 0x8000_0001, let attribute = compressionAttributes[id] {
            let declared: UInt64 = try attribute.number(8)
            guard declared == inode.size else {
                throw APFSError.invalid("La entrada sin datos no tiene un tamaño local completo")
            }
        }
        if let compressionType, compressionType != 0x8000_0001 {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            return try recoverCompressed(compressionAttributes[id]!, inodeID: id, output: output)
        }
        guard inode.size < 1_000_000_000_000 else { throw APFSError.invalid("Tamaño de archivo inválido") }
        let stream = inode.streamID
        let segments = (extents[stream] ?? []).sorted { $0.logical < $1.logical }
        if inode.size > 0, segments.isEmpty {
            throw APFSError.invalid(compressionType == 0x8000_0001
                ? "La entrada sin datos no tiene bloques locales recuperables"
                : "No se encontraron los bloques de datos de este archivo")
        }
        var covered: UInt64 = 0
        for segment in segments where segment.logical < inode.size {
            let blocks = segment.length / UInt64(blockSize) + (segment.length % UInt64(blockSize) == 0 ? 0 : 1)
            guard segment.physical < blockCount, blocks <= blockCount - segment.physical else {
                throw APFSError.invalid("Bloque APFS fuera del contenedor")
            }
            if segment.logical > covered, inode.flags & 0x200 == 0 {
                throw APFSError.invalid("Faltan bloques dentro del archivo")
            }
            if segment.physical == 0, inode.flags & 0x200 == 0 {
                throw APFSError.invalid("Un bloque de datos apunta a una zona vacía")
            }
            let (end, overflow) = segment.logical.addingReportingOverflow(segment.length)
            guard !overflow else { throw APFSError.invalid("Longitud de bloque APFS inválida") }
            covered = max(covered, min(inode.size, end))
        }
        if covered < inode.size, inode.flags & 0x200 == 0 {
            throw APFSError.invalid("Faltan bloques al final del archivo")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.truncate(atOffset: inode.size)
        for segment in segments {
            guard segment.logical < inode.size, segment.length > 0,
                  segment.physical < blockCount else { continue }
            if segment.physical == 0 { continue }
            var copied: UInt64 = 0
            let available = min(segment.length, inode.size - segment.logical)
            while copied < available {
                try cancellation.check()
                let chunk = Int(min(UInt64(1_048_576), available - copied))
                let aligned = ((chunk + 4095) / 4096) * 4096
                let data = try Self.readExactly(fd: fd,
                    offset: try byteOffset(segment.physical, extra: copied),
                    count: aligned)
                try output.seek(toOffset: segment.logical + copied)
                try output.write(contentsOf: data.prefix(chunk))
                copied += UInt64(chunk)
            }
        }
        return inode.size
    }
}
