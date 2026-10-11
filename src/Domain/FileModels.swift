import Foundation

struct DiskMeasurement: Equatable {
    var bytes: Int64 = 0
    var unreadableCount = 0
    var fileCount = 0
    var cancelled = false
    var isPartial: Bool { unreadableCount > 0 || cancelled }
}

struct FileEntry: Identifiable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let modified: Date?
    var measurement: DiskMeasurement?
    var deletion: DeletionAssessment = .review
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isHidden: Bool { name.hasPrefix(".") }
    var kind: String {
        if isSymbolicLink { return L10n.text("Enlace") }
        if isDirectory { return L10n.text("Carpeta") }
        return url.pathExtension.isEmpty ? L10n.text("Archivo") : url.pathExtension.uppercased()
    }
}

enum FileOrder: String, CaseIterable, Identifiable {
    case largest = "Más pesado primero"
    case smallest = "Menos pesado primero"
    case name = "Nombre: A → Z"
    case nameDescending = "Nombre: Z → A"
    case newest = "Más reciente primero"
    case oldest = "Más antiguo primero"
    case type = "Tipo de archivo"
    var id: String { rawValue }
    func sorts(_ a: FileEntry, _ b: FileEntry) -> Bool {
        switch self {
        case .largest, .smallest:
            if (a.measurement != nil) != (b.measurement != nil) { return a.measurement != nil }
            if a.measurement?.bytes != b.measurement?.bytes {
                return self == .largest
                    ? (a.measurement?.bytes ?? 0) > (b.measurement?.bytes ?? 0)
                    : (a.measurement?.bytes ?? 0) < (b.measurement?.bytes ?? 0)
            }
        case .newest, .oldest:
            if a.modified != b.modified {
                return self == .newest
                    ? (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
                    : (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            }
        case .type:
            if a.kind != b.kind { return a.kind.localizedStandardCompare(b.kind) == .orderedAscending }
        case .name, .nameDescending: break
        }
        let comparison = a.name.localizedStandardCompare(b.name)
        if comparison == .orderedSame { return a.id < b.id }
        return self == .nameDescending ? comparison == .orderedDescending : comparison == .orderedAscending
    }
}

enum FileKindFilter: String, CaseIterable, Identifiable {
    case all = "Todo", folders = "Carpetas", files = "Archivos"
    var id: String { rawValue }
    func includes(_ entry: FileEntry) -> Bool {
        self == .all || (self == .folders ? entry.isDirectory : !entry.isDirectory)
    }
}
