import Foundation

struct StartupItem: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let hidden: Bool
    var enabled: Bool
    var id: String { path }
    var isApplication: Bool { path.hasPrefix("/") && URL(fileURLWithPath: path).pathExtension.lowercased() == "app" }
}
