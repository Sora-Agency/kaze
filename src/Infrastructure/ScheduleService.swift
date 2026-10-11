import Foundation
import Darwin

final class ScheduleService: Sendable {
    let legacyLabel: String
    static let taskPrefix = AppIdentity.bundleIdentifier + ".task."
    let configurationURL: URL
    let legacyAgentURL: URL
    let scriptURL: URL?
    private let agentDirectory: URL
    private let runner: LaunchCommandRunning
    private let domain: String
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         scriptURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("cleaner.zsh"),
         runner: LaunchCommandRunning = LaunchCommandRunner(), userID: uid_t = getuid(),
         legacyBundleIdentifier: String? = nil) {
        legacyLabel = legacyBundleIdentifier ?? AppIdentity.discoverPreviousBundleIdentifier(home: home)
        configurationURL = home.appendingPathComponent("Library/Application Support/Kaze/schedule.json")
        agentDirectory = home.appendingPathComponent("Library/LaunchAgents")
        legacyAgentURL = agentDirectory.appendingPathComponent(legacyLabel + ".plist")
        self.scriptURL = scriptURL; self.runner = runner; domain = "gui/\(userID)"
    }
    static func label(for id: UUID) -> String { taskPrefix + id.uuidString.lowercased() }
    func agentURL(for id: UUID) -> URL { agentDirectory.appendingPathComponent(Self.label(for: id) + ".plist") }
    func load() throws -> [ScheduledCleanupTask] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [.preset] }
        let data = try Data(contentsOf: configurationURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if object?["tasks"] != nil || object?["version"] != nil {
            let store = try JSONDecoder().decode(ScheduleCollection.self, from: data)
            try store.validate()
            return store.tasks
        }
        let legacy = try JSONDecoder().decode(CleanupSchedule.self, from: data)
        try legacy.validate()
        var task = ScheduledCleanupTask.preset; task.configuration = legacy
        return [task]
    }
    func prepareForUse() throws {
        let fm = FileManager.default
        let hasJSON = fm.fileExists(atPath: configurationURL.path)
        if hasJSON {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any]
            if object?["tasks"] != nil || object?["version"] != nil {
                _ = try load()
                if object?["version"] as? Int == 3 { return }
            }
        }
        let hasAgent = fm.fileExists(atPath: legacyAgentURL.path)
        let legacyLoaded = try isRegistered(label: legacyLabel)
        guard hasJSON || hasAgent || legacyLoaded else { return }
        let tasks = try load()
        let backup = configurationURL.deletingLastPathComponent().appendingPathComponent("Backups/ScheduleMigration-\(UUID())")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        if hasJSON { try fm.copyItem(at: configurationURL, to: backup.appendingPathComponent("schedule.json")) }
        if hasAgent { try fm.copyItem(at: legacyAgentURL, to: backup.appendingPathComponent("launch-agent.plist")) }
        for url in try previousTaskAgentURLs(ids: tasks.map(\.id)) where fm.fileExists(atPath: url.path) {
            try fm.copyItem(at: url, to: backup.appendingPathComponent(url.lastPathComponent))
        }
        try commit(tasks, removeLegacy: true)
    }
    private func previousTaskAgentURLs(ids: [UUID]) throws -> [URL] {
        guard legacyLabel != AppIdentity.bundleIdentifier else { return [] }
        let prefix = legacyLabel + ".task."
        var urls: [String: URL] = [:]
        for id in ids {
            let url = agentDirectory.appendingPathComponent(prefix + id.uuidString.lowercased() + ".plist")
            urls[url.lastPathComponent] = url
        }
        if FileManager.default.fileExists(atPath: agentDirectory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: agentDirectory, includingPropertiesForKeys: nil) {
                let name = url.deletingPathExtension().lastPathComponent
                if url.pathExtension == "plist", name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil {
                    urls[url.lastPathComponent] = url
                }
            }
        }
        return urls.values.sorted { $0.path < $1.path }
    }
    private func isRegistered(label: String) throws -> Bool {
        let result = try runner.run(["print", "\(domain)/\(label)"])
        if result.status == 0 { return true }
        if result.status == 113 || result.status == 3 { return false }
        throw ScheduleError.message(L10n.text("No se pudo consultar la tarea en macOS: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"))
    }
    func isRegistered(_ id: UUID) throws -> Bool { try isRegistered(label: Self.label(for: id)) }
    func registeredIDs(in tasks: [ScheduledCleanupTask]) throws -> Set<UUID> {
        var result = Set<UUID>()
        for task in tasks { if try isRegistered(task.id) { result.insert(task.id) } }
        return result
    }
    func agentData(for task: ScheduledCleanupTask) throws -> Data {
        try task.validate()
        guard let scriptURL, FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw ScheduleError.message(L10n.text("No se encontró el motor de limpieza. Instala Kaze en Aplicaciones antes de activar una tarea."))
        }
        let intervals = task.configuration.calendarIntervals
        let plist: [String: Any] = ["Label": Self.label(for: task.id),
            "ProgramArguments": [scriptURL.path] + task.configuration.arguments + ["--task-id=\(task.id.uuidString.lowercased())"],
            "StartCalendarInterval": intervals.count == 1 ? intervals[0] as Any : intervals as Any,
            "ProcessType": "Background", "LowPriorityIO": true]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
    private func unload(label: String) throws {
        if try isRegistered(label: label) {
            let result = try runner.run(["bootout", "\(domain)/\(label)"])
            guard result.status == 0, try !isRegistered(label: label) else {
                throw ScheduleError.message(L10n.text("No se pudo desactivar la tarea: \(result.output)"))
            }
        }
    }
    private func register(label: String, url: URL) throws {
        let result = try runner.run(["bootstrap", domain, url.path])
        guard result.status == 0, try isRegistered(label: label) else {
            throw ScheduleError.message(L10n.text("macOS no pudo registrar la tarea: \(result.output)"))
        }
    }
    private struct AgentChange {
        let label: String
        let url: URL
        let previous: Data?
        let wasRegistered: Bool
        let next: Data?
    }
    private func samePlist(_ a: Data?, _ b: Data?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        guard let first = try? PropertyListSerialization.propertyList(from: a, format: nil) as? NSDictionary,
              let second = try? PropertyListSerialization.propertyList(from: b, format: nil) as? NSDictionary else { return a == b }
        return first.isEqual(second)
    }
    func saveTasks(_ tasks: [ScheduledCleanupTask]) throws { try commit(tasks, removeLegacy: false) }
    private func commit(_ tasks: [ScheduledCleanupTask], removeLegacy: Bool) throws {
        let fm = FileManager.default
        let collection = ScheduleCollection(tasks: tasks)
        try collection.validate()
        let json = try JSONEncoder().encode(collection)
        let oldTasks = try load()
        let newTasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let ids = Set(oldTasks.map(\.id)).union(tasks.map(\.id)).sorted { $0.uuidString < $1.uuidString }
        var changes: [AgentChange] = []
        for id in ids {
            let url = agentURL(for: id)
            let previous = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            let loaded = try isRegistered(id)
            let next = try newTasks[id].flatMap { $0.configuration.enabled ? try agentData(for: $0) : nil }
            if !samePlist(previous, next) || loaded != (next != nil) {
                changes.append(AgentChange(label: Self.label(for: id), url: url, previous: previous, wasRegistered: loaded, next: next))
            }
        }
        if removeLegacy {
            for url in try previousTaskAgentURLs(ids: Array(ids)) {
                let label = url.deletingPathExtension().lastPathComponent
                let previous = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
                let loaded = try isRegistered(label: label)
                if previous != nil || loaded {
                    changes.insert(AgentChange(label: label, url: url, previous: previous, wasRegistered: loaded, next: nil), at: 0)
                }
            }
            let previous = fm.fileExists(atPath: legacyAgentURL.path) ? try Data(contentsOf: legacyAgentURL) : nil
            let loaded = try isRegistered(label: legacyLabel)
            if previous != nil || loaded {
                changes.insert(AgentChange(label: legacyLabel, url: legacyAgentURL, previous: previous, wasRegistered: loaded, next: nil), at: 0)
            }
        }
        var touched: [AgentChange] = []
        do {
            try fm.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            for change in changes {
                touched.append(change)
                try unload(label: change.label)
                if let next = change.next {
                    try fm.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
                    try next.write(to: change.url, options: .atomic)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: change.url.path)
                    try register(label: change.label, url: change.url)
                } else if fm.fileExists(atPath: change.url.path) {
                    try fm.removeItem(at: change.url)
                }
            }
            try json.write(to: configurationURL, options: .atomic)
        } catch {
            let original = error
            var restorationErrors: [String] = []
            for change in touched.reversed() {
                do {
                    let current = fm.fileExists(atPath: change.url.path) ? try Data(contentsOf: change.url) : nil
                    let loaded = try isRegistered(label: change.label)
                    if samePlist(current, change.previous) && loaded == change.wasRegistered { continue }
                    try unload(label: change.label)
                    if let previous = change.previous {
                        try previous.write(to: change.url, options: .atomic)
                        if change.wasRegistered { try register(label: change.label, url: change.url) }
                    } else {
                        if fm.fileExists(atPath: change.url.path) { try fm.removeItem(at: change.url) }
                        if change.wasRegistered { throw ScheduleError.message(L10n.text("No se encontró el archivo anterior de \(change.label).")) }
                    }
                } catch { restorationErrors.append(error.localizedDescription) }
            }
            if !restorationErrors.isEmpty {
                throw ScheduleError.message(L10n.text("\(original.localizedDescription) No se pudo restaurar toda la programación anterior: \(restorationErrors.joined(separator: " "))"))
            }
            throw original
        }
    }
}
