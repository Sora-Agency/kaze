import Foundation

enum DeletionSafety: String, CaseIterable, Identifiable {
    case regenerable = "Seguros de borrar", sensitive = "Riesgo", review = "Revisar"
    var id: String { rawValue }
}

struct DeletionAssessment {
    let safety: DeletionSafety
    private let message: L10n.Message
    var explanation: String { L10n.text(message) }

    init(safety: DeletionSafety, explanation: L10n.Message) {
        self.safety = safety
        message = explanation
    }
    static let review = DeletionAssessment(safety: .review, explanation: "Puede contener datos personales. Revisa el contenido antes de borrar.")
}

func pathIsWithin(_ path: String, root: String) -> Bool {
    path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
}

enum ExplorerLocation: String, CaseIterable, Identifiable {
    case home = "Inicio", downloads = "Descargas", documents = "Documentos", desktop = "Escritorio"
    case disk = "Macintosh HD", external = "Discos externos"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .downloads: return "download"
        case .documents: return "file-text"
        case .desktop: return "monitor"
        case .disk: return "hard-drive"
        case .external: return "hard-drive"
        }
    }
    func url(home: URL) -> URL {
        switch self {
        case .home: return home
        case .downloads: return home.appendingPathComponent("Downloads")
        case .documents: return home.appendingPathComponent("Documents")
        case .desktop: return home.appendingPathComponent("Desktop")
        case .disk: return URL(fileURLWithPath: "/")
        case .external: return URL(fileURLWithPath: "/Volumes")
        }
    }
    static func active(for folder: URL, home: URL) -> ExplorerLocation {
        let path = folder.standardizedFileURL.path
        return allCases.filter { pathIsWithin(path, root: $0.url(home: home).standardizedFileURL.path) }
            .max { $0.url(home: home).path.count < $1.url(home: home).path.count } ?? .disk
    }
}
