import Foundation

struct RecoveryDiskDiscovery: Sendable {
    let runner: ToolCommandRunning
    init(runner: ToolCommandRunning = ToolCommandRunner()) { self.runner = runner }
    func devices(cancellation: OperationCancellation) throws -> [RecoveryDevice] {
        let result = try runner.run("/usr/sbin/diskutil", arguments: ["list", "-plist", "external", "physical"], cancellation: cancellation)
        let plist = try decode(result)
        return Self.devices(in: plist)
    }
    static func devices(in plist: [String: Any]) -> [RecoveryDevice] {
        let disks = plist["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        return disks.filter { ($0["OSInternal"] as? Bool) != true }.flatMap { disk in
            (disk["Partitions"] as? [[String: Any]] ?? []).compactMap { partition in
                guard partition["Content"] as? String == "Apple_APFS", let id = partition["DeviceIdentifier"] as? String,
                      id.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else { return nil }
                return RecoveryDevice(id: id, name: partition["VolumeName"] as? String ?? id,
                                      bytes: (partition["Size"] as? NSNumber)?.int64Value ?? 0)
            }
        }
    }
    func verifyExternal(_ source: RecoverySource, cancellation: OperationCancellation) throws {
        guard let physical = source.physicalDisk else { return }
        let id = String(source.url.path.dropFirst(6))
        let info = try decode(runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", id], cancellation: cancellation))
        guard info["Internal"] as? Bool == false, info["DeviceIdentifier"] as? String == id,
              (info["ParentWholeDisk"] as? String ?? id) == physical,
              ["Apple_APFS", "7C3457EF-0000-11AA-AA11-00306543ECAC"].contains(info["Content"] as? String ?? "") else {
            throw APFSError.invalid("El origen debe ser una partición APFS de un disco externo.")
        }
    }
    func validateDestination(_ destination: URL, source: RecoverySource, cancellation: OperationCancellation) throws {
        guard let physical = source.physicalDisk else { return }
        let info = try decode(runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", destination.path], cancellation: cancellation))
        guard let parent = info["APFSContainerReference"] as? String ?? info["ParentWholeDisk"] as? String ?? info["DeviceIdentifier"] as? String else {
            throw APFSError.invalid("No se pudo comprobar el disco de destino.")
        }
        var disks: Set<String> = [parent]
        if info["FilesystemType"] as? String == "apfs" {
            let topology = try decode(runner.run("/usr/sbin/diskutil", arguments: ["apfs", "list", "-plist"], cancellation: cancellation))
            guard let container = (topology["Containers"] as? [[String: Any]])?.first(where: { $0["ContainerReference"] as? String == parent }),
                  let stores = container["PhysicalStores"] as? [[String: Any]], !stores.isEmpty else {
                throw APFSError.invalid("No se pudo comprobar el disco de destino.")
            }
            let physicalDisks = stores.compactMap { store -> String? in
                guard let id = store["DeviceIdentifier"] as? String, let range = id.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return nil }
                return String(id[range])
            }
            guard physicalDisks.count == stores.count else { throw APFSError.invalid("No se pudo comprobar el disco de destino.") }
            disks.formUnion(physicalDisks)
        }
        guard !disks.contains(physical) else { throw APFSError.invalid("Guarda la recuperación en otro disco físico para proteger el origen.") }
    }
    private func decode(_ result: ToolCommandResult) throws -> [String: Any] {
        guard result.status == 0, let plist = try PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any] else {
            throw APFSError.invalid("No se pudo leer la información del disco.")
        }
        return plist
    }
}
