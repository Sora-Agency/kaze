import Foundation
import AppKit

@MainActor
final class RecoveryModel: ObservableObject {
    @Published var devicePath = ""
    @Published var imageOffset = "0"
    @Published var selectedNames = Set<String>()
    @Published private(set) var imageURL: URL?
    @Published private(set) var devices: [RecoveryDevice] = []
    @Published private(set) var volumes: [RecoveryVolume] = []
    @Published private(set) var entries: [APFSEntry] = []
    @Published private(set) var currentPath = "/"
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var status: LocalizedText = .message("Elige un disco externo o una imagen APFS para empezar.")
    @Published private(set) var outcome: RecoveryOutcome?
    @Published private(set) var selectedVolume: UInt64?
    private let service: RecoveryService
    private let discovery: RecoveryDiskDiscovery
    private let queue = DispatchQueue(label: "com.soraagency.kaze.recovery", qos: .utility)
    private var cancellation = OperationCancellation()
    private var source: RecoverySource?

    init(service: RecoveryService = RecoveryService(), discovery: RecoveryDiskDiscovery = RecoveryDiskDiscovery(), initialEntries: [APFSEntry]? = nil) {
        self.service = service; self.discovery = discovery
        if let initialEntries {
            connected = true; entries = initialEntries; status = .message("Origen en solo lectura")
        }
    }
    func detect() {
        guard !busy, !connected else { return }
        cancellation = OperationCancellation(); busy = true
        let token = cancellation, discovery = self.discovery
        queue.async {
            let result = Result { try discovery.devices(cancellation: token) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let devices):
                    self.devices = devices
                    if let device = devices.first { self.devicePath = device.rawPath; self.imageURL = nil }
                    self.status = .message(devices.isEmpty ? "No se encontró una partición APFS externa. Puedes abrir una imagen." : "Elige el disco que quieres recuperar y pulsa Abrir origen.")
                case .failure(let error): self.show(error)
                }
            }
        }
    }
    func useDevice(_ path: String) { guard !busy, !connected else { return }; devicePath = path; imageURL = nil }
    func chooseImage() {
        guard !busy, !connected else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Abrir imagen")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageURL = url; devicePath = ""; imageOffset = "0"
    }
    func connect(volumeID: UInt64? = nil) {
        guard !busy else { return }
        do {
            let selected: RecoverySource
            if let imageURL {
                guard let offset = UInt64(imageOffset), offset <= UInt64(Int64.max) - 4096 else { throw APFSError.invalid("El desplazamiento de la imagen no es válido.") }
                selected = RecoverySource(url: imageURL, offset: offset, physicalDisk: nil)
            } else { selected = try RecoverySource.device(devicePath) }
            source = selected; cancellation = OperationCancellation(); busy = true; connected = false
            entries = []; selectedNames = []; outcome = nil
            status = .message("Abriendo el origen en modo de solo lectura…")
            let token = cancellation, service = self.service
            queue.async {
                let result = Result { () -> (String, [RecoveryVolume], [APFSEntry], Int) in
                    let reader = try service.connect(selected, volumeID: volumeID, cancellation: token)
                    do { let entries = try reader.list("/"); try token.check(); return (reader.volumeName, reader.volumes, entries, reader.damagedRecords) }
                    catch { service.disconnect(); throw error }
                }
                DispatchQueue.main.async {
                    self.busy = false
                    switch result {
                    case .success(let (name, volumes, entries, damaged)):
                        self.connected = true; self.volumes = volumes; self.entries = entries; self.currentPath = "/"
                        self.selectedVolume = volumeID ?? volumes.first { $0.name == name }?.id
                        self.status = .message("\(name) · Solo lectura · \(damaged) registros ilegibles")
                    case .failure(let error): self.show(error)
                    }
                }
            }
        } catch { show(error) }
    }
    func open(_ path: String) {
        guard connected, !busy else { return }
        busy = true
        let service = self.service, token = cancellation
        queue.async {
            let result = Result { let entries = try service.list(path); try token.check(); return entries }
            if token.isCancelled { service.disconnect() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let entries): self.entries = entries; self.currentPath = path; self.selectedNames = []
                case .failure(let error): self.show(error)
                }
            }
        }
    }
    func enter(_ entry: APFSEntry) { if entry.kind == "dir" { open(path(for: entry)) } }
    func back() { open(URL(fileURLWithPath: currentPath).deletingLastPathComponent().path) }
    func path(for entry: APFSEntry) -> String { (currentPath == "/" ? "" : currentPath) + "/" + entry.name }
    func disconnect() {
        guard !busy else { return }
        connected = false; entries = []; volumes = []; selectedNames = []; source = nil
        let service = self.service
        queue.async { service.disconnect() }
    }
    func stop() { guard busy else { return }; cancellation.cancel(); status = .message("Deteniendo la lectura…") }
    func recover() {
        guard connected, !busy, !selectedNames.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L10n.text("Guardar recuperación")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let paths = entries.filter { selectedNames.contains($0.name) }.map(path(for:))
        busy = true; outcome = nil
        status = .message("Copiando los archivos a una carpeta nueva…")
        let token = cancellation, service = self.service
        queue.async {
            var lastProgress = Date.distantPast
            let result = Result {
                try service.recover(paths, in: destination, cancellation: token) { files, bytes in
                    guard Date().timeIntervalSince(lastProgress) >= 0.2 else { return }; lastProgress = Date()
                    DispatchQueue.main.async { self.status = .message("\(files) archivos copiados · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file))") }
                }
            }
            if token.isCancelled { service.disconnect() }
            DispatchQueue.main.async {
                self.busy = false
                if token.isCancelled { self.connected = false; self.entries = []; self.selectedNames = [] }
                switch result {
                case .success(let outcome):
                    self.outcome = outcome
                    self.status = .message("\(outcome.files) archivos copiados · \(outcome.failures) errores. Informe guardado con la recuperación.")
                case .failure(let error): self.show(error)
                }
            }
        }
    }
    private func show(_ error: Error) {
        if error is CancellationError { connected = false; entries = []; selectedNames = []; status = .message("Lectura detenida.") }
        else { status = .verbatim(String(describing: error)) }
    }
}
