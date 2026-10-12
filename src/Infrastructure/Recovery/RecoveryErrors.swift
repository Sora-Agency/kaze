import Foundation

enum APFSError: Error, CustomStringConvertible {
    case invalid(L10n.Message)
    var description: String {
        switch self { case .invalid(let message): return L10n.text(message) }
    }
}

struct RecoveryLimitError: LocalizedError {
    var errorDescription: String? { L10n.text("El índice APFS supera el límite de memoria. Abre una imagen más pequeña.") }
}
