import Foundation

enum AppIdentity {
    static let bundleIdentifier = "com.soraagency.kaze"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    static let previousBundleIdentifier = discoverPreviousBundleIdentifier()
    static let ownedBundleIdentifiers: Set<String> = [bundleIdentifier, previousBundleIdentifier]

    static func discoverPreviousBundleIdentifier(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        for directory in ["Library/Preferences", "Library/LaunchAgents"] {
            let entries = (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(directory), includingPropertiesForKeys: nil)) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where entry.pathExtension == "plist" {
                let name = entry.deletingPathExtension().lastPathComponent
                let identifier: String
                if let range = name.range(of: ".task.", options: .backwards), UUID(uuidString: String(name[range.upperBound...])) != nil {
                    identifier = String(name[..<range.lowerBound])
                } else {
                    identifier = name
                }
                if identifier.hasSuffix(".liberar-espacio-mac") { return identifier }
            }
        }
        return bundleIdentifier
    }

    static func migratePreferences(defaults: UserDefaults = .standard, previousDomain: [String: Any]? = nil) {
        let marker = "soraagency.preferencesMigrated"
        guard !defaults.bool(forKey: marker) else { return }
        let previous = previousDomain ?? defaults.persistentDomain(forName: previousBundleIdentifier) ?? [:]
        if defaults.object(forKey: "kaze.appearance") == nil, let appearance = previous["kaze.appearance"] as? String,
           ["dark", "light", "system"].contains(appearance) {
            defaults.set(appearance, forKey: "kaze.appearance")
        }
        defaults.set(true, forKey: marker)
    }
}
