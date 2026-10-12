// Adapted from LibreRescateNativo (MIT); see Recovery/LibreRescate-LICENSE.txt.
import Foundation
import Compression

extension APFSReader {
    func readStream(_ streamID: UInt64, at offset: UInt64, count: Int) throws -> Data {
        guard count >= 0, count <= 1_048_576 else { throw APFSError.invalid("Lectura demasiado grande") }
        var output = Data(count: count)
        var copied = 0
        let chunks = extents[streamID] ?? []
        while copied < count {
            try cancellation.check()
            let position = offset + UInt64(copied)
            guard let segment = chunks.first(where: { $0.logical <= position && position - $0.logical < $0.length }),
                  segment.physical > 0, segment.physical < blockCount else {
                throw APFSError.invalid("Faltan bloques del recurso comprimido")
            }
            let withinExtent = position - segment.logical
            let (address, overflow) = segment.physical.addingReportingOverflow(withinExtent / UInt64(blockSize))
            guard !overflow else { throw APFSError.invalid("Dirección de lectura inválida") }
            let block = try readBlock(address)
            let withinBlock = Int(withinExtent % UInt64(blockSize))
            let available = min(count - copied, blockSize - withinBlock, Int(segment.length - withinExtent))
            output.replaceSubrange(copied..<(copied + available), with: block[withinBlock..<(withinBlock + available)])
            copied += available
        }
        return output
    }

    func decode(_ payload: Data, method: UInt32, expected: Int) throws -> Data {
        guard expected >= 0, expected <= 65_536 else { throw APFSError.invalid("Bloque comprimido demasiado grande") }
        if expected == 0 {
            guard payload.isEmpty else { throw APFSError.invalid("Datos comprimidos inesperados en archivo vacío") }
            return Data()
        }
        var raw: Data?
        if method == 1 { raw = payload }
        else if (method == 3 || method == 4) && payload.first == 0xff { raw = payload.dropFirst() }
        else if (method == 7 || method == 8) && payload.first == 0x06 { raw = payload.dropFirst() }
        else if (method == 9 || method == 10) && payload.first == 0xcc { raw = payload.dropFirst() }
        else if (method == 11 || method == 12) && payload.first != 0x62 { raw = payload.dropFirst() }
        if let raw {
            guard raw.count == expected else { throw APFSError.invalid("Tamaño de bloque sin compresión inesperado") }
            return raw
        }
        let algorithm: compression_algorithm
        var encoded = payload
        switch method {
        case 3, 4: algorithm = COMPRESSION_ZLIB
        case 7, 8:
            algorithm = COMPRESSION_LZFSE
            guard payload.count <= 65_537 else { throw APFSError.invalid("Bloque LZVN demasiado grande") }
            encoded = Data("bvxn".utf8)
            var rawSize = UInt32(expected).littleEndian
            var compressedSize = UInt32(payload.count).littleEndian
            withUnsafeBytes(of: &rawSize) { encoded.append(contentsOf: $0) }
            withUnsafeBytes(of: &compressedSize) { encoded.append(contentsOf: $0) }
            encoded.append(payload)
            encoded.append(Data("bvx$".utf8))
        case 11, 12: algorithm = COMPRESSION_LZFSE
        default: throw APFSError.invalid("Compresión APFS tipo \(method) no soportada")
        }
        guard !encoded.isEmpty else { throw APFSError.invalid("Cabecera de compresión APFS inválida") }
        var result = Data(count: expected)
        let produced = result.withUnsafeMutableBytes { destination in
            encoded.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, expected,
                                          source.bindMemory(to: UInt8.self).baseAddress!, encoded.count,
                                          nil, algorithm)
            }
        }
        guard produced == expected else { throw APFSError.invalid("La descompresión produjo \(produced) de \(expected) bytes") }
        return result
    }

    func recoverCompressed(_ attribute: Data, inodeID: UInt64, output: FileHandle) throws -> UInt64 {
        guard attribute.count >= 16, try attribute.bytes(0, 4) == Data("fpmc".utf8) else {
            throw APFSError.invalid("Cabecera de compresión APFS inválida")
        }
        let method: UInt32 = try attribute.number(4)
        let size: UInt64 = try attribute.number(8)
        guard size < 1_000_000_000_000 else { throw APFSError.invalid("Tamaño comprimido inválido") }
        try output.truncate(atOffset: size)
        try output.seek(toOffset: 0)
        if method & 1 == 1, method != 0x8000_0001 {
            guard size <= 65_536 else { throw APFSError.invalid("Atributo de compresión interno demasiado grande") }
            let contents = try decode(attribute.subdata(in: 16..<attribute.count), method: method, expected: Int(size))
            try output.write(contentsOf: contents)
            return size
        }
        guard method == 8 || method == 10 || method == 12,
              let (stream, forkSize) = resourceStreams[inodeID], forkSize >= 8 else {
            throw APFSError.invalid("Compresión APFS tipo \(method) aún no soportada")
        }
        let blocks = Int((size + 65_535) / 65_536)
        guard blocks < 1_000_000 else { throw APFSError.invalid("Tabla de compresión demasiado grande") }
        let first = try readStream(stream, at: 0, count: 4)
        let firstOffset: UInt32 = try first.number(0)
        guard firstOffset >= UInt32((blocks + 1) * 4), UInt64(firstOffset) < forkSize else {
            throw APFSError.invalid("Tabla de bloques comprimidos inválida")
        }
        for index in 0..<blocks {
            try cancellation.check()
            let pair = try readStream(stream, at: UInt64(index * 4), count: 8)
            let start: UInt32 = try pair.number(0)
            let end: UInt32 = try pair.number(4)
            guard start >= firstOffset, end > start, UInt64(end) <= forkSize,
                  end - start <= 65_537 else {
                throw APFSError.invalid("Bloque comprimido fuera del recurso")
            }
            let payload = try readStream(stream, at: UInt64(start), count: Int(end - start))
            let expected = Int(min(UInt64(65_536), size - UInt64(index) * 65_536))
            let contents = try decode(payload, method: method, expected: expected)
            try output.write(contentsOf: contents)
        }
        return size
    }

}
