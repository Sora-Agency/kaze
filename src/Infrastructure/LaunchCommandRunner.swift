import Foundation

struct LaunchCommandResult: Sendable { let status: Int32; let output: String }
protocol LaunchCommandRunning: Sendable { func run(_ arguments: [String]) throws -> LaunchCommandResult }
struct LaunchCommandRunner: LaunchCommandRunning {
    func run(_ arguments: [String]) throws -> LaunchCommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return LaunchCommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
}
