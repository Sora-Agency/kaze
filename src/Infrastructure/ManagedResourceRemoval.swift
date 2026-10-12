import Foundation

enum ManagedResourceRemoval {
    static func validIdentifier(_ resource: ManagedResource) -> Bool {
        switch resource.kind {
        case .dockerImage: return resource.identifier.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil
        case .dockerContainer: return resource.identifier.range(of: "^[a-f0-9]{12,64}$", options: .regularExpression) != nil
        case .dockerVolume: return resource.identifier.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
        case .xcodeDevice: return UUID(uuidString: resource.identifier) != nil
        case .xcodeRuntime: return resource.identifier.range(of: "^com\\.apple\\.CoreSimulator\\.SimRuntime\\.[A-Za-z0-9.-]+$", options: .regularExpression) != nil
        }
    }
    static func remove(_ resource: ManagedResource, journal: OperationJournal = .shared) -> (output: String, status: Int32) {
        guard resource.canSelect, validIdentifier(resource) else { return (L10n.text("Identificador de recurso no válido"), 1) }
        do {
            let catalog = try RuleCatalog.bundled()
            let processes = CleanerOperations.runCommand("/bin/ps", arguments: ["-axo", "comm="], timeout: 3)
            guard processes.status == 0 else { throw AnalysisActionError.changed }
            try catalog.authorizeNative(resource.kind == .xcodeDevice || resource.kind == .xcodeRuntime ? "simulator-resource" : "docker-resource", processes: processes.output)
            let lease = try MutationLease(); defer { withExtendedLifetime(lease) {} }
            var record = try journal.begin(url: URL(fileURLWithPath: resource.identifier), title: resource.title, bytes: resource.sizeBytes > 0 ? resource.sizeBytes : nil, ruleVersion: catalog.manifest.version)
            record.originalPath = resource.kind.rawValue + ": " + resource.identifier; try journal.write(record)
            let before = (try? FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data")[.systemFreeSize] as? NSNumber)?.int64Value
            let result: (output: String, status: Int32)
            switch resource.kind {
            case .dockerImage: result = CleanerOperations.runDocker(arguments: ["image", "rm", resource.identifier])
            case .dockerContainer: result = CleanerOperations.runDocker(arguments: ["container", "rm", resource.identifier])
            case .dockerVolume: result = CleanerOperations.runDocker(arguments: ["volume", "rm", resource.identifier])
            case .xcodeDevice:
                let state = CleanerOperations.runCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"], timeout: 5)
                guard state.status == 0, let data = state.output.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let groups = root["devices"] as? [String: [[String: Any]]],
                      let device = groups.values.flatMap({ $0 }).first(where: { $0["udid"] as? String == resource.identifier }),
                      device["state"] as? String == "Shutdown" else {
                    record.status = "failed"; record.detail = "El simulador está en uso o no se pudo verificar."; try journal.write(record)
                    return (L10n.text("Apaga el simulador antes de eliminarlo"), 1)
                }
                result = CleanerOperations.runCommand("/usr/bin/xcrun", arguments: ["simctl", "delete", resource.identifier])
            case .xcodeRuntime: result = CleanerOperations.runCommand("/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", resource.identifier])
            }
            record.originalPath = resource.kind.rawValue + ": " + resource.identifier
            record.status = result.status == 0 ? "completed" : "failed"
            record.freedBytes = nil
            if let before, let after = (try? FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data")[.systemFreeSize] as? NSNumber)?.int64Value {
                record.observedFreeDelta = after - before
            }
            record.detail = result.status == 0 ? "Recurso administrado: sin deshacer; tamaño liberado no verificable por archivo." : result.output
            try journal.write(record)
            return result
        } catch { return (error.localizedDescription, 1) }
    }
}
