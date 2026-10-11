import Foundation

@main
struct IdentityTests {
    static func main() throws {
        let name = "kaze.identity.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); print("PASS: \(message)")
        }
        AppIdentity.migratePreferences(defaults: defaults, previousDomain: ["kaze.appearance": "light", "unrelated": "do not copy"])
        check(defaults.string(forKey: "kaze.appearance") == "light", "Sora Agency preserves the previous appearance")
        check(defaults.object(forKey: "unrelated") == nil, "Migration copies only known preferences")
        defaults.set("dark", forKey: "kaze.appearance")
        AppIdentity.migratePreferences(defaults: defaults, previousDomain: ["kaze.appearance": "light"])
        check(defaults.string(forKey: "kaze.appearance") == "dark", "Repeated migration preserves changes in the new app")
        defaults.removePersistentDomain(forName: name)
        defaults.set("dark", forKey: "kaze.appearance")
        AppIdentity.migratePreferences(defaults: defaults, previousDomain: ["kaze.appearance": "light"])
        check(defaults.string(forKey: "kaze.appearance") == "dark", "Existing new-domain preferences take precedence")
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("kaze.identity.\(UUID())")
        defer { try? fm.removeItem(at: home) }
        check(AppIdentity.discoverPreviousBundleIdentifier(home: home) == AppIdentity.bundleIdentifier, "New installs use the current namespace")
        let preferences = home.appendingPathComponent("Library/Preferences")
        try fm.createDirectory(at: preferences, withIntermediateDirectories: true)
        let previous = "org.example.liberar-espacio-mac"
        let file = preferences.appendingPathComponent(previous + ".plist")
        try Data().write(to: file)
        check(AppIdentity.discoverPreviousBundleIdentifier(home: home) == previous, "Previous preferences are found without a fixed owner namespace")
        try fm.removeItem(at: file)
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at: agents, withIntermediateDirectories: true)
        try Data().write(to: agents.appendingPathComponent(previous + ".task.\(UUID()).plist"))
        check(AppIdentity.discoverPreviousBundleIdentifier(home: home) == previous, "Existing task agents identify a previous installation")
        check(AppIdentity.bundleIdentifier == "com.soraagency.kaze", "The bundle belongs to Sora Agency")
    }
}
