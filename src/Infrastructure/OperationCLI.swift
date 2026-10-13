import Foundation
import Darwin

enum OperationCLI {
    static func runIfRequested() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first, command.hasPrefix("--kaze-journal-") || command.hasPrefix("--kaze-authorize-") else { return }
        _ = setpriority(PRIO_PROCESS, 0, 10)
        do {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let catalog = try RuleCatalog(directory: resources.appendingPathComponent("Rules"))
            let home = FileManager.default.homeDirectoryForCurrentUser
            let journal = OperationJournal(home: home)
            switch command {
            case "--kaze-authorize-command":
                let wanted = Array(arguments.dropFirst())
                let processes = CleanerOperations.runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
                guard processes.status == 0, catalog.manifest.rules.contains(where: { rule in
                    (rule.commands ?? []).contains(wanted) && !rule.closedProcesses.contains(where: { processes.output.localizedCaseInsensitiveContains($0) })
                }) else { throw CocoaError(.fileWriteNoPermission) }
            case "--kaze-authorize-cleanup":
                guard arguments.count == 2 else { throw CocoaError(.fileReadCorruptFile) }
                let processes = CleanerOperations.runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
                guard processes.status == 0,
                      CleanupAuthorization.rule(for: URL(fileURLWithPath: arguments[1]), home: home, catalog: catalog, processes: processes.output) != nil else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                let index = StorageIndexer.scan(roots: [URL(fileURLWithPath: arguments[1])], home: home, cancellation: ScanCancellation(), limit: 1)
                guard !index.partial, let root = index.files.first, !root.containsProtected else { throw CocoaError(.fileWriteNoPermission) }
                print(index.allocated)
            case "--kaze-journal-begin":
                guard arguments.count == 4 else { throw CocoaError(.fileReadCorruptFile) }
                let bytes = Int64(arguments[3])
                guard bytes.map({ $0 >= 0 }) ?? (arguments[3] == "unknown") else { throw CocoaError(.fileReadCorruptFile) }
                let record = try journal.begin(url: URL(fileURLWithPath: arguments[1]), title: arguments[2], bytes: bytes, ruleVersion: catalog.manifest.version)
                print(record.id.uuidString)
            case "--kaze-journal-finish":
                guard (4...5).contains(arguments.count), let id = UUID(uuidString: arguments[1]), let status = Int32(arguments[2]) else { throw CocoaError(.fileReadCorruptFile) }
                let file = journal.directory.appendingPathComponent(id.uuidString + ".json")
                var record = try JSONDecoder().decode(OperationRecord.self, from: Data(contentsOf: file))
                record.status = status == 0 ? "completed" : "failed"; record.detail = arguments[3]
                record.freedBytes = nil
                if arguments.count == 5 { record.observedFreeDelta = Int64(arguments[4]) }
                try journal.write(record)
            default: throw CocoaError(.fileReadCorruptFile)
            }
            exit(0)
        } catch {
            fputs("Kaze: rule or operation journal verification failed.\n", stderr)
            exit(1)
        }
    }
}
