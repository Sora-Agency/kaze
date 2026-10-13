import Foundation

struct TrashTarget {
    let url: URL
    let directory: Bool
    var fingerprint: FileFingerprint? = nil
    var authorizationID: UUID? = nil

    init(url: URL, directory: Bool, fingerprint: FileFingerprint? = nil) {
        self.url = url; self.directory = directory; self.fingerprint = fingerprint
    }
    init(_ file: IndexedFile, authorizationID: UUID? = nil) {
        self.init(url: file.url, directory: file.directory, fingerprint: file.fingerprint)
        self.authorizationID = authorizationID
    }
}

struct ReviewedTrashRequest: Identifiable {
    let id = UUID()
    let target: TrashTarget
    let fingerprint: FileFingerprint
}

enum ReviewedTrashError: LocalizedError {
    case protectedItem, cancelled
    var errorDescription: String? {
        switch self {
        case .protectedItem: return L10n.text("Este elemento está protegido. Los componentes del sistema, respaldos, bibliotecas de Photos y archivos sincronizados no se mueven desde este menú.")
        case .cancelled: return L10n.text("Traslado cancelado. El elemento se conserva.")
        }
    }
}
