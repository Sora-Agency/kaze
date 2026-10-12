import Foundation
import Darwin

struct RecoveryCopyOperation {
    let reader: RecoveryFileReading
    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0") && name.utf8.count <= 255
    }
    func run(_ paths: [String], in destination: URL, cancellation: OperationCancellation,
             progress: (Int, UInt64) -> Void) throws -> RecoveryOutcome {
        try cancellation.check()
        // A new private directory, with exclusive creation, prevents overwrites.
        let root = destination.resolvingSymlinksInPath().appendingPathComponent("Kaze-Recovery-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(root.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        var files = 0, failures = 0, visited = 0
        var bytes: UInt64 = 0
        var errors: [String] = []
        var cancelled = false
        func failure(_ path: String, _ error: Error) {
            failures += 1
            if errors.count < 1000 { errors.append("\(path): \(error)") }
        }
        func copy(_ path: String, _ target: URL, _ kind: String, depth: Int, ancestors: Set<UInt64>) throws {
            try cancellation.check()
            visited += 1
            guard visited <= 1_000_000, depth <= 100 else { throw RecoveryLimitError() }
            if kind == "dir" {
                guard mkdir(target.path, 0o700) == 0 else { throw CocoaError(.fileWriteFileExists) }
                for child in try reader.list(path) {
                    guard Self.safeName(child.name), !ancestors.contains(child.id) else {
                        failure(path, APFSError.invalid("Nombre o ciclo de carpeta inválido.")); continue
                    }
                    do { try copy(path + "/" + child.name, target.appendingPathComponent(child.name), child.kind,
                                  depth: depth + 1, ancestors: ancestors.union([child.id])) }
                    catch { if error is CancellationError || error is RecoveryLimitError { throw error }; failure(path + "/" + child.name, error) }
                }
            } else if kind == "file" {
                let fd = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard fd >= 0 else { throw CocoaError(.fileWriteFileExists) }
                close(fd)
                do { bytes += try reader.recoverFile(path, to: target); files += 1; progress(files, bytes) }
                catch { try? FileManager.default.removeItem(at: target); throw error }
            } else { throw APFSError.invalid("Este tipo de archivo todavía no está soportado.") }
        }
        for path in paths {
            do {
                let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard path.hasPrefix("/"), !parts.isEmpty, parts.allSatisfy(Self.safeName) else { throw APFSError.invalid("Ruta de recuperación inválida.") }
                let parent = "/" + parts.dropLast().joined(separator: "/")
                guard let entry = try reader.list(parent).first(where: { $0.name == parts.last }) else { throw APFSError.invalid("El archivo ya no está disponible.") }
                try copy(path, root.appendingPathComponent(entry.name), entry.kind, depth: 0, ancestors: [entry.id])
            } catch {
                if error is CancellationError { cancelled = true; break }
                failure(path, error)
                if error is RecoveryLimitError { break }
            }
        }
        let report = "Kaze Recovery\n\(Date().ISO8601Format())\n\(reader.volumeName)\n" +
            L10n.text("Archivos: \(files) · Bytes copiados: \(bytes) · Errores: \(failures) · Registros ilegibles: \(reader.damagedRecords)") +
            "\n" + L10n.text(cancelled ? "Recuperación detenida. Se conservaron los archivos completos." : "Recuperación finalizada.") + "\n\n" + errors.joined(separator: "\n")
        try report.write(to: root.appendingPathComponent("recovery_report.txt"), atomically: true, encoding: .utf8)
        return RecoveryOutcome(folder: root, files: files, bytes: bytes, failures: failures, damagedRecords: reader.damagedRecords, cancelled: cancelled)
    }
}
