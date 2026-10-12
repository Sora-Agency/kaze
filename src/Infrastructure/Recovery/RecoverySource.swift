import Foundation
import Darwin

import KazeRecoveryAuth

struct RecoverySource: Equatable {
    let url: URL
    let offset: UInt64
    let physicalDisk: String?

    static func device(_ path: String) throws -> RecoverySource {
        guard path.range(of: #"^/dev/rdisk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw APFSError.invalid("Elige una partición APFS externa válida.")
        }
        let identifier = String(path.dropFirst(6))
        guard let range = identifier.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { throw APFSError.invalid("Elige una partición APFS externa válida.") }
        return RecoverySource(url: URL(fileURLWithPath: path), offset: 0, physicalDisk: String(identifier[range]))
    }

    func openReadOnly(cancellation: OperationCancellation) throws -> Int32 {
        let descriptor: Int32
        if physicalDisk != nil {
            descriptor = url.path.withCString { path in
                kaze_authorize_readonly(path, { context in
                    guard let context else { return 1 }
                    return Unmanaged<OperationCancellation>.fromOpaque(context).takeUnretainedValue().isCancelled ? 1 : 0
                }, Unmanaged.passUnretained(cancellation).toOpaque())
            }
        } else {
            descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if descriptor >= 0 {
                var info = stat()
                if fstat(descriptor, &info) != 0 || info.st_mode & S_IFMT != S_IFREG { close(descriptor); throw APFSError.invalid("La imagen debe ser un archivo local regular.") }
            }
        }
        if cancellation.isCancelled { if descriptor >= 0 { close(descriptor) }; throw CancellationError() }
        guard descriptor >= 0 else { throw APFSError.invalid("No se autorizó la lectura del origen.") }
        return descriptor
    }
}
