import Foundation

enum FindingGroup: String, CaseIterable, Identifiable {
    case safe = "Limpieza segura", review = "Elementos para revisar", applications = "Aplicaciones"
    case duplicates = "Duplicados", development = "Desarrollo"
    var id: String { rawValue }
    var icon: String {
        switch self { case .safe: return "shield-check"; case .review: return "circle-alert"
        case .applications: return "layout-grid"; case .duplicates: return "file"; case .development: return "hammer" }
    }
}

struct FileFingerprint: Codable, Equatable, Hashable {
    let device: Int64, inode: UInt64, size: Int64, modified: Int64, nanoseconds: Int64
    var changed: Int64 = 0
    var changedNanoseconds: Int64 = 0
}

struct IndexedFile: Identifiable, Codable {
    let url: URL
    let parent: Int?
    let directory: Bool
    let symbolicLink: Bool
    let protected: Bool
    let fingerprint: FileFingerprint
    let links: UInt16
    let ownAllocated: Int64
    var logical: Int64
    var allocated: Int64
    var potentialAllocated: Int64 = 0
    let modified: Date
    var partial = false
    var containsProtected = false
    var detailsLimited = false
    var systemKind: SystemDataKind? = nil
    var id: String { url.path }
}

struct StorageIndex: Codable {
    let date: Date
    let roots: [URL]
    let home: URL
    var files: [IndexedFile]
    var children: [Int: [Int]] = [:]
    var byPath: [String: Int] = [:]
    var unreadable = 0
    var omitted = 0
    var candidateOmitted = 0
    var cancelled = false
    var scannedCount = 0
    var systemTotals: [SystemDataKind: AnalysisBytes] = [:]
    var systemLocations: [SystemDataKind: [Int]] = [:]
    var eventID: UInt64 = 0
    private enum CodingKeys: String, CodingKey {
        case date, roots, home, files, unreadable, omitted, candidateOmitted, cancelled, scannedCount
        case systemTotals, systemLocations, eventID
    }
    var partial: Bool { unreadable > 0 || cancelled }
    var logical: Int64 { (children[-1] ?? []).reduce(0) { $0 + files[$1].logical } }
    var allocated: Int64 { (children[-1] ?? []).reduce(0) { $0 + files[$1].allocated } }
    static let empty = StorageIndex(date: Date(), roots: [], home: URL(fileURLWithPath: "/"), files: [], children: [:], byPath: [:])
}

struct CleanupRule: Codable, Identifiable {
    let id: String
    let title: String
    let paths: [String]
    let projectFolder: String?
    let manifests: [String]?
    let category: String
    let regenerable: Bool
    let reason: String
    let recovery: String
    let closedProcesses: [String]
    let commands: [[String]]?
    var nativeAction: String? = nil
}

struct RuleManifest: Codable {
    let schema: Int
    let version: Int
    let rules: [CleanupRule]
}

struct StorageFinding: Identifiable {
    let node: Int
    let group: FindingGroup
    let rule: CleanupRule?
    let potential: Int64
    var id: Int { node }
}

struct AnalysisBytes: Codable {
    var logical: Int64 = 0
    var allocated: Int64 = 0
    var partial = false
}

struct DuplicateGroup: Identifiable, Codable {
    let id: String
    let nodes: [Int]
    let similar: Bool
    let potential: Int64
}

struct DuplicateReport: Codable {
    var exact: [DuplicateGroup] = []
    var similar: [DuplicateGroup] = []
    var examined = 0
    var visualExamined = 0
    var skipped = 0
    var partial = false
}

enum SystemDataKind: String, CaseIterable, Codable {
    case caches = "Cachés", simulators = "Simuladores", backups = "Respaldos iOS"
    case logs = "Logs", support = "Datos de aplicaciones", other = "Otros datos del sistema"
}

enum AnalysisProtection {
    static func duplicateEligible(_ url: URL, home: URL) -> Bool {
        let path = url.path
        if pathIsWithin(path, root: home.path) {
            let first = path.dropFirst(home.path.count + 1).split(separator: "/").first
            if first == "Library" || first?.hasPrefix(".") == true { return false }
        } else if ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/dev", "/cores"].contains(where: { pathIsWithin(path, root: $0) }) { return false }
        return !path.split(separator: "/").contains {
            ["node_modules", "Pods", ".build", ".git", ".gradle", ".venv"].contains(String($0))
                || $0.hasSuffix(".app") || $0.hasSuffix(".framework") || $0.hasSuffix(".kext")
        }
    }
    static func opaque(_ url: URL, home: URL) -> Bool {
        let path = url.path.lowercased()
        let relative = String(path.dropFirst(home.path.count + 1))
        return relative.hasPrefix("library/cloudstorage") || relative.hasPrefix("library/mobile documents")
            || path.split(separator: "/").contains { [".trash", ".timemachine", "backups.backupdb"].contains(String($0))
                || $0.hasSuffix(".backupbundle") || $0.hasSuffix(".sparsebundle")
                || $0.hasPrefix("dropbox") || $0.hasPrefix("onedrive") || $0.hasPrefix("googledrive") }
    }
    static func isProtected(_ url: URL, home: URL) -> Bool {
        let path = url.path
        let relative = String(path.dropFirst(home.path.count + 1)).lowercased()
        let components = path.lowercased().split(separator: "/")
        return components.contains { [".trash", ".timemachine", "backups.backupdb", "backup", "backups"].contains(String($0))
            || $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".photolibrary") || $0.hasSuffix(".backupbundle")
            || $0.hasSuffix(".sparsebundle") }
            || relative.hasPrefix("library/mobile documents") || relative.hasPrefix("library/cloudstorage")
            || relative.hasPrefix("library/application support/mobilesync")
            || components.contains { $0.hasPrefix("dropbox") || $0.hasPrefix("onedrive") || $0.hasPrefix("googledrive") }
    }
    static func systemKind(_ url: URL, home: URL) -> SystemDataKind? {
        let path = url.path.lowercased()
        guard pathIsWithin(url.path, root: home.appendingPathComponent("Library").path)
            || pathIsWithin(url.path, root: "/Library") || pathIsWithin(url.path, root: "/private/var") else { return nil }
        if path.contains("/mobilesync/backup") { return .backups }
        if path.contains("/coresimulator/") || path.hasSuffix("/coresimulator") { return .simulators }
        if path.contains("/caches/") || path.hasSuffix("/caches") || path.contains("/deriveddata/") || path.hasSuffix("/deriveddata") { return .caches }
        if path.contains("/logs/") || path.hasSuffix("/logs") { return .logs }
        if path.contains("/application support/") || path.hasSuffix("/application support") || path.contains("/containers/") || path.hasSuffix("/containers") || path.contains("/group containers/") || path.hasSuffix("/group containers") { return .support }
        return .other
    }
}
