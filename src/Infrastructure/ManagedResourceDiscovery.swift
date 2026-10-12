import Foundation
import AppKit

extension CleanerOperations {
    nonisolated static func dockerExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.docker/bin/docker"
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated static func runDocker(
        arguments: [String],
        timeout: TimeInterval = 20
    ) -> (output: String, status: Int32) {
        guard let executable = dockerExecutable() else { return (L10n.text("Docker CLI no está instalado"), 127) }
        return runCommand(executable, arguments: arguments, timeout: timeout)
    }

    nonisolated static func jsonLines(_ text: String) -> [[String: Any]] {
        text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return value
        }
    }

    nonisolated static func parseByteCount(_ text: String) -> Int64 {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let pattern = #"^([0-9]+(?:\.[0-9]+)?)([A-Za-z]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              let numberRange = Range(match.range(at: 1), in: compact),
              let unitRange = Range(match.range(at: 2), in: compact),
              let number = Double(compact[numberRange]) else { return 0 }

        let unit = compact[unitRange].lowercased()
        let multiplier: Double
        switch unit {
        case "kb": multiplier = 1_000
        case "mb": multiplier = 1_000_000
        case "gb": multiplier = 1_000_000_000
        case "tb": multiplier = 1_000_000_000_000
        case "kib": multiplier = 1_024
        case "mib": multiplier = 1_048_576
        case "gib": multiplier = 1_073_741_824
        case "tib": multiplier = 1_099_511_627_776
        default: multiplier = 1
        }
        return Int64(number * multiplier)
    }

    nonisolated static func discoverDockerResources() -> [ManagedResource] {
        var resources: [ManagedResource] = []
        var imageIDs = Set<String>()

        let images = runDocker(arguments: ["image", "ls", "-a", "--no-trunc", "--format", "{{json .}}"])
        if images.status == 0 {
            for item in jsonLines(images.output) {
                let identifier = item["ID"] as? String ?? ""
                guard !identifier.isEmpty, imageIDs.insert(identifier).inserted else { continue }
                let repository = item["Repository"] as? String ?? "<none>"
                let tag = item["Tag"] as? String ?? "<none>"
                let size = item["Size"] as? String
                let created = item["CreatedSince"] as? String ?? ""
                resources.append(ManagedResource(
                    id: "docker-image:\(identifier)",
                    kind: .dockerImage,
                    identifier: identifier,
                    title: "\(repository):\(tag)",
                    detail: .verbatim(created.isEmpty ? String(identifier.prefix(20)) : "\(String(identifier.prefix(20))) · \(created)"),
                    sizeText: size.map(LocalizedText.verbatim) ?? .message("Tamaño no informado"),
                    sizeBytes: parseByteCount(size ?? ""),
                    canSelect: true,
                    blockedReason: nil
                ))
            }
        }

        let containers = runDocker(arguments: ["container", "ls", "-a", "--size", "--no-trunc", "--format", "{{json .}}"])
        if containers.status == 0 {
            for item in jsonLines(containers.output) {
                let identifier = item["ID"] as? String ?? ""
                guard !identifier.isEmpty else { continue }
                let name = item["Names"] as? String ?? String(identifier.prefix(12))
                let image = item["Image"] as? String ?? ""
                let state = (item["State"] as? String ?? "").lowercased()
                let status = item["Status"] as? String ?? state
                let size = item["Size"] as? String
                let isRunning = state == "running" || status.lowercased().hasPrefix("up ")
                resources.append(ManagedResource(
                    id: "docker-container:\(identifier)",
                    kind: .dockerContainer,
                    identifier: identifier,
                    title: name,
                    detail: .verbatim([image, status].filter { !$0.isEmpty }.joined(separator: " · ")),
                    sizeText: size.map(LocalizedText.verbatim) ?? .message("Tamaño no informado"),
                    sizeBytes: parseByteCount(size ?? ""),
                    canSelect: !isRunning,
                    blockedReason: isRunning ? .message("Detén el contenedor antes de eliminarlo") : nil
                ))
            }
        }

        let volumes = runDocker(arguments: ["volume", "ls", "--format", "{{json .}}"])
        if volumes.status == 0 {
            for item in jsonLines(volumes.output) {
                let name = item["Name"] as? String ?? ""
                guard !name.isEmpty else { continue }
                let driver = item["Driver"] as? String ?? "local"
                resources.append(ManagedResource(
                    id: "docker-volume:\(name)",
                    kind: .dockerVolume,
                    identifier: name,
                    title: name,
                    detail: .message("Driver \(driver) · Docker impedirá borrarlo si está en uso"),
                    sizeText: .message("Tamaño incluido en Docker.raw"),
                    sizeBytes: 0,
                    canSelect: true,
                    blockedReason: nil
                ))
            }
        }

        return resources
    }

    nonisolated static func discoverXcodeResources() -> [ManagedResource] {
        var resources: [ManagedResource] = []
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser

        let devicesResult = runCommand(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"],
            timeout: 12
        )
        if devicesResult.status == 0,
           let data = devicesResult.output.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let groups = root["devices"] as? [String: [[String: Any]]] {
            for (runtime, devices) in groups {
                for device in devices {
                    let identifier = device["udid"] as? String ?? ""
                    guard !identifier.isEmpty else { continue }
                    let name = device["name"] as? String ?? identifier
                    let state = device["state"] as? String ?? L10n.text("Desconocido")
                    let path = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(identifier)")
                    let bytes = diskUsage(of: path)
                    resources.append(ManagedResource(
                        id: "xcode-device:\(identifier)",
                        kind: .xcodeDevice,
                        identifier: identifier,
                        title: name,
                        detail: .verbatim("\(runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "").replacingOccurrences(of: "-", with: " ")) · \(state)"),
                        sizeText: bytes > 0 ? .verbatim(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) : .message("Sin datos locales"),
                        sizeBytes: bytes,
                        canSelect: state.lowercased() != "booted",
                        blockedReason: state.lowercased() == "booted" ? .message("Apaga el simulador antes de eliminarlo") : nil
                    ))
                }
            }
        }

        let runtimesResult = runCommand(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "runtimes", "--json"],
            timeout: 12
        )
        if runtimesResult.status == 0,
           let data = runtimesResult.output.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let runtimes = root["runtimes"] as? [[String: Any]] {
            for runtime in runtimes {
                let identifier = runtime["identifier"] as? String ?? ""
                let name = runtime["name"] as? String ?? identifier
                let version = runtime["version"] as? String ?? ""
                let bundlePath = runtime["bundlePath"] as? String ?? ""
                let isDownloadedRuntime = bundlePath.hasPrefix("/Library/Developer/CoreSimulator/")
                    || bundlePath.hasPrefix(home.appendingPathComponent("Library/Developer/CoreSimulator").path)
                guard !identifier.isEmpty else { continue }
                let bytes = bundlePath.isEmpty ? 0 : diskUsage(of: URL(fileURLWithPath: bundlePath))
                resources.append(ManagedResource(
                    id: "xcode-runtime:\(identifier)",
                    kind: .xcodeRuntime,
                    identifier: identifier,
                    title: name,
                    detail: version.isEmpty ? .verbatim(identifier) : .message("Versión \(version)"),
                    sizeText: bytes > 0 ? .verbatim(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) : .message("Tamaño no informado"),
                    sizeBytes: bytes,
                    canSelect: isDownloadedRuntime,
                    blockedReason: isDownloadedRuntime ? nil : .message("Runtime incluido con Xcode; no se elimina por separado")
                ))
            }
        }

        return resources
    }

}
