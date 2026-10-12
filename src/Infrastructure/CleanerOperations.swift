import Foundation
import AppKit
import Darwin

enum CleanerOperations {
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LiberarEspacioMac/limpieza.log")
    }

    @discardableResult
    nonisolated static func recycle(_ url: URL, label: String, bytes: Int64? = nil) -> Bool {
        guard DiskScanner.metadata(url) != nil else { return false }
        do {
            let catalog = try RuleCatalog.bundled(); try catalog.authorizeNative("trash")
            try OperationJournal.shared.trash(url, title: label, bytes: bytes, ruleVersion: catalog.manifest.version) { source in
                do {
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
                    return destination as URL?
                } catch {
                    let initialError = error
                    let semaphore = DispatchSemaphore(value: 0)
                    var destination: URL?
                    DispatchQueue.main.async {
                        NSWorkspace.shared.recycle([source]) { mapping, _ in
                            destination = mapping[source]
                            semaphore.signal()
                        }
                    }
                    guard semaphore.wait(timeout: .now() + 45) == .success else { throw AnalysisActionError.pendingTrash }
                    if DiskScanner.metadata(source) == nil { return destination }
                    if let privileged = privilegedRecycle(source, label: label, log: logURL) { return privileged }
                    throw initialError
                }
            }
            writeLog(L10n.text("A Papelera: \(label) — \(url.path)"), to: logURL)
            return true
        } catch {
            writeLog(L10n.text("ERROR al mover \(label) a la Papelera: \(url.path) — \(error.localizedDescription). "), to: logURL)
            return false
        }
    }

    nonisolated static func closeApplication(_ identifier: String, bundleURL: URL? = nil) -> Bool {
        let target = bundleURL.map(canonicalFilePath)
        func belongs(_ app: NSRunningApplication) -> Bool {
            guard let target, let url = app.bundleURL else { return true }
            return canonicalFilePath(url) == target
        }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter(belongs)
        apps.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter(belongs).isEmpty else { return false }
        guard let bundleURL else { return true }
        let processes = runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
        guard processes.status == 0 else { return false }
        let prefix = canonicalFilePath(bundleURL) + "/"
        return !processes.output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
    }

    nonisolated static func privilegedRecycle(_ url: URL, label: String, log: URL) -> URL? {
        let manager = FileManager.default
        let trash = manager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        var destination = trash.appendingPathComponent(url.lastPathComponent)
        if manager.fileExists(atPath: destination.path) {
            let suffix = String(UUID().uuidString.prefix(8))
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let name = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            destination = trash.appendingPathComponent(name)
        }

        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let prompt = L10n.text("Kaze necesita autorización para mover este elemento a la Papelera.")
        let script = """
        set sourcePath to "\(escaped(url.path))"
        set destinationPath to "\(escaped(destination.path))"
        do shell script "/bin/mv -n " & quoted form of sourcePath & " " & quoted form of destinationPath with administrator privileges with prompt "\(escaped(prompt))"
        """
        let result = runCommand("/usr/bin/osascript", arguments: ["-e", script], timeout: 180)
        if result.status == 0 && !manager.fileExists(atPath: url.path) {
            writeLog(L10n.text("A Papelera con autorización: \(label) — \(url.path)"), to: log)
            return destination
        }
        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        writeLog(L10n.text("Autorización fallida para \(label): \(detail)"), to: log)
        return nil
    }

    nonisolated static func writeLog(_ message: String, to destination: URL) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let line = "\(timestamp) \(message)\n"
        let data = Data(line.utf8)
        let manager = FileManager.default
        try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path), let handle = try? FileHandle(forWritingTo: destination) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: destination)
        }
    }

    nonisolated static func runCommand(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 20
    ) -> (output: String, status: Int32) {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return (L10n.text("No se encontró \(executable)"), 127)
        }

        let manager = FileManager.default
        let outputURL = manager.temporaryDirectory
            .appendingPathComponent("liberar-espacio-\(UUID().uuidString).log")
        guard manager.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return (L10n.text("No se pudo crear el archivo temporal de salida"), 125)
        }
        defer {
            try? outputHandle.close()
            try? manager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DOCKER_CLIENT_TIMEOUT"] = "4"
        environment["DOCKER_HTTP_TIMEOUT"] = "4"
        process.environment = environment

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            let didTimeOut = process.isRunning
            if didTimeOut {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.25)
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            try? outputHandle.synchronize()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            var output = String(data: data, encoding: .utf8) ?? ""
            if didTimeOut {
                output += output.isEmpty ? L10n.text("Tiempo de espera agotado") : L10n.text("\nTiempo de espera agotado")
            }
            return (output, didTimeOut ? 124 : process.terminationStatus)
        } catch {
            return (error.localizedDescription, 126)
        }
    }

    nonisolated static func diskUsage(of url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }

        let result = runCommand("/usr/bin/du", arguments: ["-sk", url.path], timeout: 8)
        guard result.status == 0,
              let kib = Int64(result.output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "") else {
            return 0
        }
        return kib * 1024
    }
}
