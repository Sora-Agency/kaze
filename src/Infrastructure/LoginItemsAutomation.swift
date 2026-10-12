import Foundation

protocol LoginItemsManaging {
    func list() throws -> [StartupItem]
    func set(_ item: StartupItem, enabled: Bool) throws
}

struct LoginItemsAutomation: LoginItemsManaging {
    let runner: ToolCommandRunning
    init(runner: ToolCommandRunning = ToolCommandRunner(timeout: 60)) { self.runner = runner }
    func list() throws -> [StartupItem] {
        let data = try execute("list", item: nil)
        let items = try JSONDecoder().decode([StartupItem].self, from: data)
        guard items.count <= 2000 else { throw StartupItemsError.tooManyItems }
        return items
    }
    func set(_ item: StartupItem, enabled: Bool) throws {
        guard item.isApplication else { throw StartupItemsError.invalidApplication }
        _ = try execute(enabled ? "enable" : "disable", item: item)
    }
    private func execute(_ action: String, item: StartupItem?) throws -> Data {
        let payload = item.map { try? JSONEncoder().encode($0) } ?? nil
        let json = payload.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let result = try runner.run("/usr/bin/osascript", arguments: ["-l", "JavaScript", "-e", Self.script, action, json], cancellation: OperationCancellation())
        guard result.status == 0 else {
            let output = String(decoding: result.data, as: UTF8.self)
            if output.contains("-1743") { throw StartupItemsError.permission }
            throw StartupItemsError.automation
        }
        return result.data
    }
    // Arguments are JSON data, never interpolated into executable script text.
    static let script = #"""
    function run(args) {
        const system = Application('System Events');
        const action = args[0], item = JSON.parse(args[1]);
        if (action === 'list') {
            return JSON.stringify(system.loginItems().map(function(entry) {
                return {name: entry.name(), path: entry.path(), hidden: entry.hidden(), enabled: true};
            }));
        }
        const matches = system.loginItems().filter(function(entry) { return entry.path() === item.path; });
        if (action === 'disable') {
            matches.forEach(function(entry) { entry.delete(); });
        } else if (action === 'enable' && matches.length === 0) {
            system.loginItems.push(system.LoginItem({path: item.path, hidden: item.hidden}));
        } else if (action !== 'enable') { throw new Error('Unknown action'); }
        return '{}';
    }
    """#
}
