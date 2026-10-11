import Foundation

struct StorageSnapshot {
    var total: Int64 = 0
    var free: Int64 = 0

    var used: Int64 { max(0, total - free) }
    var fractionUsed: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct ApplicationDataItem: Identifiable, Hashable {
    let id: String
    let applicationID: String
    let url: URL
    let bytes: Int64
    let isDirectory: Bool

    var displayPath: String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

struct InstalledApplication: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let appBytes: Int64
    let relatedData: [ApplicationDataItem]

    var relatedURLs: [URL] { relatedData.map(\.url) }
    var relatedBytes: Int64 { relatedData.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { appBytes + relatedBytes }
}

enum ManagedResourceKind: String, Hashable, CaseIterable {
    case dockerImage = "Imagen Docker"
    case dockerContainer = "Contenedor Docker"
    case dockerVolume = "Volumen Docker"
    case xcodeDevice = "Simulador Xcode"
    case xcodeRuntime = "Runtime Xcode"

    var icon: String {
        switch self {
        case .dockerImage: return "box"
        case .dockerContainer: return "box"
        case .dockerVolume: return "hard-drive"
        case .xcodeDevice: return "smartphone"
        case .xcodeRuntime: return "layout-grid"
        }
    }
}

struct ManagedResource: Identifiable, Hashable {
    let id: String
    let kind: ManagedResourceKind
    let identifier: String
    let title: String
    let detailText: LocalizedText
    let sizeLabel: LocalizedText
    let sizeBytes: Int64
    let canSelect: Bool
    let blockedText: LocalizedText?

    var detail: String { detailText.string }
    var sizeText: String { sizeLabel.string }
    var blockedReason: String? { blockedText?.string }

    init(id: String, kind: ManagedResourceKind, identifier: String, title: String,
         detail: LocalizedText, sizeText: LocalizedText, sizeBytes: Int64, canSelect: Bool,
         blockedReason: LocalizedText?) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.title = title
        detailText = detail
        sizeLabel = sizeText
        self.sizeBytes = sizeBytes
        self.canSelect = canSelect
        blockedText = blockedReason
    }
}
