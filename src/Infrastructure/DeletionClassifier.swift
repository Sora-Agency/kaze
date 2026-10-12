import Foundation
import Darwin

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

extension CachedExplorerEntry {
    func entry(classifier: DeletionClassifier) -> FileEntry {
        FileEntry(url: url, isDirectory: directory, isSymbolicLink: symbolicLink, modified: modified,
                  measurement: measurement, deletion: classifier.assess(url, isSymbolicLink: symbolicLink, metadataAvailable: fingerprint != nil))
    }
}
