import Foundation

final class FakeLoginItems: LoginItemsManaging {
    var items: [StartupItem] = []
    var fails = false
    var calls = 0
    func list() throws -> [StartupItem] { calls += 1; return items }
    func set(_ item: StartupItem, enabled: Bool) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        items.removeAll { $0.path == item.path }
        if enabled { items.append(StartupItem(name: item.name, path: item.path, hidden: item.hidden, enabled: true)) }
    }
}
struct MockJXARunner: ToolCommandRunning {
    func run(_ executable: String, arguments: [String], cancellation: OperationCancellation) throws -> ToolCommandResult {
        // Evaluate the production script with a mock Application. Never send an Apple event.
        let fake = #"""
        var entries = [{name: function(){return 'Quoted " App';}, path: function(){return '/Applications/Quoted " App.app';}, hidden: function(){return true;}, delete: function(){entries=[];}}];
        function MockApplication(name) {
          function loginItems() { return entries; }
          loginItems.push = function(item) { entries.push({name:function(){return item.name;},path:function(){return item.path;},hidden:function(){return item.hidden;}}); };
          return {loginItems:loginItems, LoginItem:function(value){if(value.name!==undefined)throw new Error('name is read-only');value.name=value.path.split('/').pop().replace(/\.app$/, '');return value;}};
        }
        """#
        var modified = arguments
        modified[3] = fake + "\n" + arguments[3].replacingOccurrences(of: "function run(args) {", with: "function run(args) {\nconst Application = MockApplication;")
        return try ToolCommandRunner().run(executable, arguments: modified, cancellation: cancellation)
    }
}
@main struct StartupItemsTests {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("Kaze-Startup-Test-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Quoted \" Café.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let item = StartupItem(name: "Quoted \" Café", path: app.path, hidden: true, enabled: true)
        let fake = FakeLoginItems(); fake.items = [item]
        let service = StartupItemsService(home: root, manager: fake)
        precondition(fake.calls == 0, "Initialization must not read login items")
        let disabled = try service.set(item, enabled: false)
        precondition(disabled.count == 1 && !disabled[0].enabled && disabled[0].hidden)
        let reloaded = StartupItemsService(home: root, manager: fake)
        let persisted = try reloaded.load(); precondition(persisted == disabled)
        let enabled = try reloaded.set(disabled[0], enabled: true)
        precondition(enabled.count == 1 && enabled[0].enabled && enabled[0].hidden)
        fake.fails = true
        do { _ = try service.set(item, enabled: false); fatalError("Expected failure") } catch {}
        let actual = try service.load(); precondition(actual[0].enabled, "Failed disable must retain actual state")
        fake.fails = false
        _ = try service.set(item, enabled: false)
        try fm.removeItem(at: app)
        do { _ = try service.set(item, enabled: true); fatalError("Must reject missing apps") } catch {}
        let data = StartupItem(name: "Document", path: root.appendingPathComponent("data.txt").path, hidden: false, enabled: true)
        do { _ = try service.set(data, enabled: false); fatalError("Must reject non-app items") }
        catch StartupItemsError.invalidApplication {}
        let automation = LoginItemsAutomation(runner: MockJXARunner())
        let scripted = try automation.list()
        precondition(scripted.count == 1 && scripted[0].hidden && scripted[0].name == "Quoted \" App")
        try automation.set(scripted[0], enabled: false)
        try automation.set(item, enabled: true)
        // Timeout is bounded even when a command never responds.
        do { _ = try ToolCommandRunner(timeout: 0.15).run("/bin/sleep", arguments: ["10"], cancellation: OperationCancellation()); fatalError("Expected timeout") }
        catch ToolCommandError.timeout {}
        print("Startup: reversible persistence, failed mutations, missing apps, JSON/JXA and command timeout passed")
    }
}
