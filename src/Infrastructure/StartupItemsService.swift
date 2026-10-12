import Foundation

final class StartupItemsService {
    private let manager: LoginItemsManaging
    private let store: URL
    private let lockURL: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, manager: LoginItemsManaging = LoginItemsAutomation()) {
        self.manager = manager
        store = home.appendingPathComponent("Library/Application Support/Kaze/Startup/disabled-v1.json")
        lockURL = home.appendingPathComponent("Library/Application Support/Kaze/Startup/mutation.lock")
    }
    func load() throws -> [StartupItem] {
        let active = try manager.list()
        let disabled = try saved()
        var items: [String: StartupItem] = [:]
        for item in disabled where item.isApplication { items[item.path] = StartupItem(name: item.name, path: item.path, hidden: item.hidden, enabled: false) }
        for item in active { items[item.path] = item }
        return items.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func set(_ requested: StartupItem, enabled: Bool) throws -> [StartupItem] {
        guard requested.isApplication else { throw StartupItemsError.invalidApplication }
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lease = try MutationLease(url: lockURL)
        defer { withExtendedLifetime(lease) {} }
        let active = try manager.list()
        var disabled = try saved()
        if enabled {
            let values = try URL(fileURLWithPath: requested.path).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw StartupItemsError.missingApplication }
            try manager.set(requested, enabled: true)
        } else if let current = active.first(where: { $0.path == requested.path }) {
            // Save before mutation so interrupted/failed operations remain reversible.
            disabled.removeAll { $0.path == current.path }
            disabled.append(StartupItem(name: current.name, path: current.path, hidden: current.hidden, enabled: false))
            try persist(disabled)
            try manager.set(current, enabled: false)
        }
        let verified = try manager.list().contains { $0.path == requested.path }
        guard verified == enabled else { throw StartupItemsError.unconfirmed }
        if enabled { disabled.removeAll { $0.path == requested.path }; try persist(disabled) }
        return try load()
    }
    private func saved() throws -> [StartupItem] {
        guard FileManager.default.fileExists(atPath: store.path) else { return [] }
        let size = try store.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 1_048_576 else { throw StartupItemsError.oversizedStore }
        return try JSONDecoder().decode([StartupItem].self, from: Data(contentsOf: store))
    }
    private func persist(_ items: [StartupItem]) throws {
        let data = try JSONEncoder().encode(items)
        guard data.count <= 1_048_576 else { throw StartupItemsError.oversizedStore }
        try data.write(to: store, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
    }
}
