import Foundation
import Darwin

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

struct DeletionClassifier {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func assess(_ url: URL, isSymbolicLink: Bool = false, metadataAvailable: Bool = true) -> DeletionAssessment {
        guard metadataAvailable else {
            return DeletionAssessment(safety: .review, explanation: "No se pudo leer este elemento para evaluar su ubicación.")
        }
        guard !isSymbolicLink else {
            return DeletionAssessment(safety: .review, explanation: "Enlace simbólico: revisa su destino antes de modificarlo.")
        }
        let path = canonicalFilePath(url)
        let homePath = canonicalFilePath(home)
        let caches = ["Library/Caches", "Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator/Caches"]
        if caches.contains(where: { pathIsWithin(path, root: homePath + "/" + $0) }) {
            return DeletionAssessment(safety: .regenerable, explanation: "Caché o archivos de compilación regenerables. Cierra la aplicación que los usa antes de borrarlos; puede tener que descargarlos o generarlos de nuevo.")
        }
        let protected = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/dev", "/cores"]
        if path == "/" || (!pathIsWithin(path, root: homePath) && protected.contains(where: { pathIsWithin(path, root: $0) })) {
            return DeletionAssessment(safety: .sensitive, explanation: "Contiene componentes del sistema o de aplicaciones. Borrarlos puede impedir su funcionamiento.")
        }
        if pathIsWithin(path, root: homePath + "/Library") ||
            (pathIsWithin(path, root: homePath) && path.dropFirst(homePath.count + 1).split(separator: "/").first?.hasPrefix(".") == true && !pathIsWithin(path, root: homePath + "/.Trash")) {
            return DeletionAssessment(safety: .sensitive, explanation: "Puede contener configuración, credenciales o datos de aplicaciones. Borrarlo puede causar pérdida de datos o fallos.")
        }
        if ["app", "framework", "kext", "dylib"].contains(url.pathExtension.lowercased()) {
            return DeletionAssessment(safety: .sensitive, explanation: "Componente de una aplicación. Usa un desinstalador o revisa sus dependencias antes de eliminarlo.")
        }
        return .review
    }
}

func canonicalFilePath(_ url: URL) -> String {
    var parent = url.standardizedFileURL
    var tail: [String] = []
    while true {
        let resolved: String? = parent.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer, let real = realpath(pointer, nil) else { return nil }
            defer { free(real) }
            return String(cString: real)
        }
        if let resolved {
            return tail.reversed().reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
        }
        guard parent.path != "/" else { return url.standardizedFileURL.path }
        tail.append(parent.lastPathComponent)
        parent.deleteLastPathComponent()
    }
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
