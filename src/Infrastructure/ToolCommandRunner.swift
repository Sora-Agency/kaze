import Foundation
import Darwin

enum ToolCommandError: Error, CustomStringConvertible {
    case outputLimit, timeout
    var description: String {
        switch self {
        case .outputLimit: return L10n.text("La respuesta del sistema supera el límite de lectura.")
        case .timeout: return L10n.text("El sistema no respondió a tiempo. Inténtalo otra vez.")
        }
    }
}

struct ToolCommandResult: Sendable {
    let status: Int32
    let data: Data
}

protocol ToolCommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], cancellation: OperationCancellation) throws -> ToolCommandResult
}

struct ToolCommandRunner: ToolCommandRunning {
    let timeout: TimeInterval
    init(timeout: TimeInterval = 30) { self.timeout = timeout }
    func run(_ executable: String, arguments: [String], cancellation: OperationCancellation) throws -> ToolCommandResult {
        try cancellation.check()
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watchdog.schedule(deadline: .now(), repeating: .milliseconds(100))
        watchdog.setEventHandler {
            if process.isRunning && (cancellation.isCancelled || Date() >= deadline) { kill(process.processIdentifier, SIGKILL) }
        }
        watchdog.resume()
        defer { watchdog.cancel(); try? pipe.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= 2_097_152 else {
                kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
                throw ToolCommandError.outputLimit
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        try cancellation.check()
        guard Date() < deadline else { throw ToolCommandError.timeout }
        return ToolCommandResult(status: process.terminationStatus, data: data)
    }
}
