import Foundation

final class TestLaunchRunner: LaunchCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = Set<String>()
    private var failBootstrap: String?
    private var failBootout: String?
    private var calls: [[String]] = []
    var commands: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    func rejectNextBootstrap(_ label: String) { lock.lock(); failBootstrap = label; lock.unlock() }
    func rejectNextBootout(_ label: String) { lock.lock(); failBootout = label; lock.unlock() }
    func run(_ arguments: [String]) throws -> LaunchCommandResult {
        lock.lock(); defer { lock.unlock() }; calls.append(arguments)
        switch arguments.first {
        case "print": return LaunchCommandResult(status: loaded.contains(arguments[1].split(separator: "/").last.map(String.init)!) ? 0 : 113, output: "")
        case "bootstrap":
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: arguments[2])), format: nil) as! [String: Any]
            let label = plist["Label"] as! String
            if failBootstrap == label { failBootstrap = nil; return LaunchCommandResult(status: 5, output: "Test rejection") }
            loaded.insert(label)
        case "bootout":
            let label = arguments[1].split(separator: "/").last.map(String.init)!
            if failBootout == label { failBootout = nil; return LaunchCommandResult(status: 5, output: "Test rejection") }
            loaded.remove(label)
        default: fatalError("Unexpected launch command")
        }
        return LaunchCommandResult(status: 0, output: "")
    }
}

@main
struct ScheduleTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("kaze schedule \(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let script = root.appendingPathComponent("Kaze App/cleaner.zsh")
        try fm.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/zsh\nexit 99\n".utf8).write(to: script)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let runner = TestLaunchRunner()
        let service = ScheduleService(home: root, scriptURL: script, runner: runner, legacyBundleIdentifier: "org.example.liberar-espacio-mac")
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }; print("PASS: \(message)")
        }
        func rejected(_ action: () throws -> Void, _ message: String) {
            do { try action(); fatalError(message) } catch { print("PASS: \(message)") }
        }
        func registered(_ id: UUID) -> Bool { try! service.isRegistered(id) }
        func plist(_ task: ScheduledCleanupTask) throws -> [String: Any] {
            try PropertyListSerialization.propertyList(from: service.agentData(for: task), format: nil) as! [String: Any]
        }
        let defaults = try service.load()
        check(defaults.count == 1 && !defaults[0].configuration.enabled && defaults[0].configuration.timeText == "09:30", "Preset is 09:30 and inactive")
        let model = ScheduledTaskModel(service: service)
        check(model.registeredIDs.isEmpty && !runner.commands.contains { $0.first == "bootstrap" }, "Opening the scheduler cannot activate a default task")
        var first = ScheduledCleanupTask(name: "Cachés generales")
        first.configuration.hour = 15; first.configuration.minute = 45
        first.configuration.thresholdGiB = 120
        first.configuration.developmentCaches = false; first.configuration.dockerCaches = false
        first.configuration.notifications = false
        var second = ScheduledCleanupTask(name: "Desarrollo")
        second.configuration.hour = 18; second.configuration.minute = 0
        second.configuration.frequency = .weekdays
        second.configuration.generalCaches = false; second.configuration.dockerCaches = false
        try service.saveTasks([first, second])
        check(try! service.load() == [first, second], "Multiple inactive tasks persist their independent settings")
        check(!fm.fileExists(atPath: service.agentURL(for: first.id).path) && !fm.fileExists(atPath: service.agentURL(for: second.id).path), "Saving inactive tasks installs no agents")
        first.configuration.enabled = true
        try service.saveTasks([first, second])
        check(registered(first.id) && !registered(second.id), "Activating one task keeps the other inactive")
        second.configuration.enabled = true
        try service.saveTasks([first, second])
        check(registered(first.id) && registered(second.id) && ScheduleService.label(for: first.id) != ScheduleService.label(for: second.id), "Two active tasks use separate launchd labels")
        let data = try plist(first)
        let args = data["ProgramArguments"] as! [String]
        check(args.first == script.path && args.contains("--threshold-gib=120") && args.contains("--skip-development") && args.contains("--skip-docker") && args.contains("--quiet"), "Each task passes its own categories, threshold and notifications; paths with spaces are preserved")
        check(data["RunAtLoad"] == nil && data["KeepAlive"] == nil && !runner.commands.contains { ["kickstart", "start"].contains($0.first ?? "") }, "Activating tasks does not run cleanup immediately")
        check((data["StartCalendarInterval"] as! [String: Int]) == ["Hour": 15, "Minute": 45], "Daily intervals use the selected time")
        let weekdays = try plist(second)["StartCalendarInterval"] as! [[String: Int]]
        check(weekdays.compactMap { $0["Weekday"] } == [2,3,4,5,6], "Weekdays create five correct calendar intervals")
        let marker = runner.commands.count
        let secondAgent = try Data(contentsOf: service.agentURL(for: second.id))
        first.configuration.hour = 16; first.configuration.onlyWhenLowSpace = false
        try service.saveTasks([first, second])
        let mutations = runner.commands.dropFirst(marker).filter { ["bootout", "bootstrap"].contains($0.first ?? "") }
        check(mutations.count == 2 && !mutations.contains { $0.joined(separator: " ").contains(second.id.uuidString.lowercased()) }, "Editing one active task does not reload another task")
        check(try! Data(contentsOf: service.agentURL(for: second.id)) == secondAgent && registered(second.id), "Unrelated agent files and registrations are unchanged")
        check(first.configuration.arguments.contains("--always"), "Unconditional cleanup uses an explicit cleaner flag")
        let renameMarker = runner.commands.count
        first.name = "Nuevo nombre"
        try service.saveTasks([first, second])
        check(!runner.commands.dropFirst(renameMarker).contains { ["bootout", "bootstrap"].contains($0.first ?? "") }, "Renaming a task persists without restarting any job")
        var weekly = second; weekly.configuration.frequency = .weekly; weekly.configuration.weekday = 7
        check(weekly.configuration.calendarIntervals == [["Hour": 18, "Minute": 0, "Weekday": 7]], "Weekly scheduling uses the chosen day")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 19))!
        let next = second.configuration.nextRun(after: friday, calendar: calendar)!
        check(calendar.component(.weekday, from: next) == 2 && calendar.component(.day, from: next) == 12, "Next weekday run skips the weekend")
        let oldJSON = try Data(contentsOf: service.configurationURL)
        let oldFirst = try Data(contentsOf: service.agentURL(for: first.id))
        var changed = first; changed.configuration.hour = 17
        runner.rejectNextBootstrap(ScheduleService.label(for: first.id))
        rejected({ try service.saveTasks([changed, second]) }, "Registration failure is reported")
        check(registered(first.id) && registered(second.id) && (try! Data(contentsOf: service.configurationURL)) == oldJSON && (try! Data(contentsOf: service.agentURL(for: first.id))) == oldFirst, "Failed edits restore the previous task and retain the collection")
        runner.rejectNextBootout(ScheduleService.label(for: first.id))
        rejected({ try service.saveTasks([second]) }, "A failed deletion cannot silently discard an active task")
        check(registered(first.id) && (try! service.load()).count == 2, "Failed deletion keeps both tasks stored")
        first.configuration.enabled = false
        try service.saveTasks([first, second])
        check(!registered(first.id) && registered(second.id), "Disabling one task preserves the other active task")
        try service.saveTasks([first])
        check(!registered(second.id) && !fm.fileExists(atPath: service.agentURL(for: second.id).path), "Deleting an active task unloads and removes only its agent")
        try service.saveTasks([])
        check((try! service.load()).isEmpty, "Deleting every task persists an empty list without recreating the preset")
        var invalid = first; invalid.name = " \n "
        rejected({ try service.saveTasks([invalid]) }, "Blank task names are rejected")
        invalid = first; invalid.configuration.hour = 24
        rejected({ try service.saveTasks([invalid]) }, "Invalid hours are rejected")
        invalid = first; invalid.configuration.thresholdGiB = 0
        rejected({ try service.saveTasks([invalid]) }, "Invalid thresholds are rejected")
        invalid = first; invalid.configuration.enabled = true; invalid.configuration.generalCaches = false
        rejected({ try service.saveTasks([invalid]) }, "An active task requires a category")
        rejected({ try service.saveTasks([first, first]) }, "Duplicate task identities are rejected")
        let missing = ScheduleService(home: root, scriptURL: root.appendingPathComponent("missing"), runner: runner)
        var active = first; active.configuration.enabled = true
        rejected({ try missing.saveTasks([active]) }, "Missing cleaner engines cannot be scheduled")
        var legacy = CleanupSchedule(); legacy.enabled = true; legacy.hour = 20; legacy.thresholdGiB = 80; legacy.dockerCaches = false
        try JSONEncoder().encode(legacy).write(to: service.configurationURL)
        let oldPlist: [String: Any] = ["Label": service.legacyLabel, "ProgramArguments": [script.path, "--scheduled"], "StartCalendarInterval": ["Hour":20,"Minute":30]]
        try PropertyListSerialization.data(fromPropertyList: oldPlist, format: .xml, options: 0).write(to: service.legacyAgentURL)
        _ = try runner.run(["bootstrap", "gui/501", service.legacyAgentURL.path])
        let legacyJSON = try Data(contentsOf: service.configurationURL)
        runner.rejectNextBootstrap(ScheduleService.label(for: ScheduledCleanupTask.presetID))
        rejected({ try service.prepareForUse() }, "Migration registration failure is reported")
        let legacyStatus = try runner.run(["print", "gui/501/" + service.legacyLabel])
        check(legacyStatus.status == 0 && (try! Data(contentsOf: service.configurationURL)) == legacyJSON && fm.fileExists(atPath: service.legacyAgentURL.path), "Failed migration restores the legacy job and retains its preferences")
        try service.prepareForUse()
        let migrated = try service.load()
        check(migrated.count == 1 && migrated[0].configuration == legacy && migrated[0].id == ScheduledCleanupTask.presetID && registered(migrated[0].id), "Legacy explicit activation and options migrate to one independent task")
        check(!fm.fileExists(atPath: service.legacyAgentURL.path), "Migration removes the obsolete single-task agent")
        let beforeRepeat = runner.commands.count
        try service.prepareForUse()
        check(runner.commands.count == beforeRepeat, "Migration is idempotent")
        try service.saveTasks([])
        try fm.removeItem(at: service.configurationURL)
        try PropertyListSerialization.data(fromPropertyList: oldPlist, format: .xml, options: 0).write(to: service.legacyAgentURL)
        _ = try runner.run(["bootstrap", "gui/501", service.legacyAgentURL.path])
        try service.prepareForUse()
        check(!(try! service.load())[0].configuration.enabled && !registered(ScheduledCleanupTask.presetID), "Legacy automatic scheduling without explicit preferences stays disabled")
        let backups = try fm.contentsOfDirectory(atPath: service.configurationURL.deletingLastPathComponent().appendingPathComponent("Backups").path)
        check(backups.count == 3, "Both migration scenarios and failed attempts preserve backups")
        let asyncModel = ScheduledTaskModel(service: service)
        func finish() {
            let deadline = Date().addingTimeInterval(5)
            while asyncModel.isSaving && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(!asyncModel.isSaving && asyncModel.error == nil, "Async scheduler mutation succeeds")
        }
        asyncModel.upsert(first); finish()
        asyncModel.upsert(second); finish()
        check(asyncModel.tasks.contains { $0.id == first.id } && asyncModel.tasks.contains { $0.id == second.id }, "The UI creates independent tasks")
        asyncModel.setEnabled(first.id, true); finish()
        asyncModel.setEnabled(first.id, false); finish()
        check(asyncModel.isEnabled(second) && !asyncModel.isEnabled(first), "UI toggles operate on the selected task")
        asyncModel.delete(first.id); finish()
        check(!asyncModel.tasks.contains { $0.id == first.id } && asyncModel.isEnabled(second), "The UI deletes one task while preserving another")
        let migrationHome = root.appendingPathComponent("Sora Migration")
        let migrationRunner = TestLaunchRunner()
        let migrationService = ScheduleService(home: migrationHome, scriptURL: script, runner: migrationRunner, legacyBundleIdentifier: "org.example.liberar-espacio-mac")
        try fm.createDirectory(at: migrationService.configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let agents = migrationHome.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at: agents, withIntermediateDirectories: true)
        var a = ScheduledCleanupTask(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "General nocturna")
        a.configuration.enabled = true; a.configuration.hour = 23; a.configuration.minute = 15
        a.configuration.developmentCaches = false; a.configuration.dockerCaches = false
        var b = ScheduledCleanupTask(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "Docker semanal")
        b.configuration.enabled = true; b.configuration.frequency = .weekly; b.configuration.weekday = 7
        b.configuration.generalCaches = false; b.configuration.developmentCaches = false
        let c = ScheduledCleanupTask(name: "Desactivada")
        let originalTasks = [a, b, c]
        let previousJSON = try JSONEncoder().encode(ScheduleCollection(version: 2, tasks: originalTasks))
        try previousJSON.write(to: migrationService.configurationURL)
        var previousAgents: [URL] = []
        for task in [a, b] {
            let oldLabel = migrationService.legacyLabel + ".task." + task.id.uuidString.lowercased()
            let url = agents.appendingPathComponent(oldLabel + ".plist")
            var data = try plist(task); data["Label"] = oldLabel
            try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: url)
            _ = try migrationRunner.run(["bootstrap", "gui/501", url.path])
            previousAgents.append(url)
        }
        migrationRunner.rejectNextBootstrap(ScheduleService.label(for: b.id))
        rejected({ try migrationService.prepareForUse() }, "A namespace migration failure is reported")
        check(migrationRunner.commands.contains { $0.first == "bootstrap" && $0.last == migrationService.agentURL(for: b.id).path }, "Rollback test reaches the new registration instead of failing during backup")
        for url in previousAgents {
            let status = try migrationRunner.run(["print", "gui/501/" + url.deletingPathExtension().lastPathComponent])
            check(status.status == 0 && fm.fileExists(atPath: url.path), "Failed namespace migration restores the previous active agent")
        }
        check((try! Data(contentsOf: migrationService.configurationURL)) == previousJSON && !(try! migrationService.isRegistered(a.id)), "Failed migration retains schema 2 preferences and removes new jobs")
        try migrationService.prepareForUse()
        check((try! migrationService.load()) == originalTasks, "Migration preserves UUIDs, names, times, categories and inactive tasks")
        check((try! migrationService.isRegistered(a.id)) && (try! migrationService.isRegistered(b.id)) && !(try! migrationService.isRegistered(c.id)), "Only previously active tasks are registered in the Sora Agency namespace")
        check(previousAgents.allSatisfy { !fm.fileExists(atPath: $0.path) }, "Old task agents are removed after migration")
        let saved = try JSONDecoder().decode(ScheduleCollection.self, from: Data(contentsOf: migrationService.configurationURL))
        check(saved.version == 3 && ScheduleService.label(for: a.id).hasPrefix("com.soraagency.kaze.task."), "New schema and job labels belong to Sora Agency")
        let count = migrationRunner.commands.count
        try migrationService.prepareForUse()
        check(migrationRunner.commands.count == count, "Namespace migration runs only once")
        rejected({ try ScheduleCollection(version: 99, tasks: []).validate() }, "Unknown schema versions cannot overwrite tasks")
        let currentHome = root.appendingPathComponent("Current Namespace")
        let currentRunner = TestLaunchRunner()
        let currentService = ScheduleService(home: currentHome, scriptURL: script, runner: currentRunner)
        try currentService.saveTasks([a, b])
        try JSONEncoder().encode(ScheduleCollection(version: 2, tasks: [a, b])).write(to: currentService.configurationURL)
        let currentMarker = currentRunner.commands.count
        try currentService.prepareForUse()
        check((try! currentService.isRegistered(a.id)) && (try! currentService.isRegistered(b.id)), "Schema migration retains jobs already using the current namespace")
        check(!currentRunner.commands.dropFirst(currentMarker).contains { ["bootstrap", "bootout"].contains($0.first ?? "") }, "Current namespace migration does not unload current tasks")
        print("All multiple-task scheduling tests passed.")
    }
}
