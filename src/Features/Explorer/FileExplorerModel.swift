import Foundation
import AppKit
import Combine

@MainActor
final class FileExplorerModel: ObservableObject {
    @Published private(set) var folder = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var isScanning = false
    @Published private(set) var error: String?
    @Published private var statusText = LocalizedText.message("Elige una carpeta para analizar su contenido.")
    @Published private(set) var hasLoaded = false
    @Published private(set) var cancelled = false
    @Published private(set) var backHistory: [URL] = []
    @Published private(set) var forwardHistory: [URL] = []
    @Published var search = ""
    @Published var order: FileOrder = .largest
    @Published var filter: FileKindFilter = .all
    @Published var showHidden = true
    @Published var safetyFilter: DeletionSafety? = nil
    private let classifier: DeletionClassifier
    private var cancellation = ScanCancellation()
    private var generation = UUID()
    private let queue = DispatchQueue(label: "kaze.disk-scanner", qos: .utility)

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         initialEntries: [FileEntry]? = nil) {
        classifier = DeletionClassifier(home: home)
        self.folder = URL(fileURLWithPath: folder.standardizedFileURL.path, isDirectory: true)
        if let initialEntries {
            entries = initialEntries
            totalBytes = initialEntries.reduce(0) { $0 + ($1.measurement?.bytes ?? 0) }
            hasLoaded = true
            statusText = .count("scan.complete", initialEntries.count)
        }
    }

    var status: String { statusText.string }

    var visibleEntries: [FileEntry] {
        entries.filter { (showHidden || !$0.isHidden) && filter.includes($0)
            && (safetyFilter == nil || $0.deletion.safety == safetyFilter)
            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted(by: order.sorts)
    }
    var incompleteCount: Int { entries.filter { $0.measurement == nil || $0.measurement?.isPartial == true }.count }
    var breadcrumbs: [URL] {
        var result = [folder]
        var current = folder
        while current.path != "/" { current.deleteLastPathComponent(); result.insert(current, at: 0) }
        return result
    }

    func open(_ url: URL, recordHistory: Bool = true) {
        let target = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
        if recordHistory && target.path != folder.path { backHistory.append(folder); forwardHistory.removeAll() }
        folder = target
        search = ""
        scan()
    }
    func back() {
        guard let target = backHistory.popLast() else { return }
        forwardHistory.append(folder); open(target, recordHistory: false)
    }
    func forward() {
        guard let target = forwardHistory.popLast() else { return }
        backHistory.append(folder); open(target, recordHistory: false)
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.showsHiddenFiles = true; panel.prompt = L10n.text("Analizar carpeta")
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func stop() {
        cancellation.cancel()
        generation = UUID()
        isScanning = false
        cancelled = true
        statusText = .message("Análisis detenido. Actualiza para completar los tamaños pendientes.")
    }
    func scan() {
        cancellation.cancel()
        let token = ScanCancellation()
        cancellation = token
        let request = UUID()
        generation = request
        let target = folder
        let classifier = self.classifier
        entries = []; totalBytes = 0; error = nil; isScanning = true; hasLoaded = true; cancelled = false
        statusText = .message("Leyendo contenido…")
        queue.async { [weak self] in
            do {
                guard !token.isCancelled else { return }
                let items = try DiskScanner.entries(at: target, cancellation: token, classifier: classifier)
                guard !token.isCancelled else { return }
                var total: Int64 = 0
                var seen = Set<DiskFileIdentity>()
                func accumulate(_ info: stat) {
                    guard seen.insert(DiskFileIdentity(info)).inserted else { return }
                    total += Int64(info.st_blocks) * 512
                }
                if let info = DiskScanner.metadata(target) { accumulate(info) }
                for item in items where !item.isDirectory {
                    if let info = DiskScanner.metadata(item.url) { accumulate(info) }
                }
                let initialTotal = total
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.entries = items
                    self.totalBytes = initialTotal
                    self.statusText = .count("scan.calculating", items.count)
                }
                for item in items where item.isDirectory {
                    guard !token.isCancelled else { return }
                    DispatchQueue.main.async {
                        guard let self, self.generation == request else { return }
                        self.statusText = .message("Analizando \(item.name)…")
                    }
                    let measurement = DiskScanner.measure(item.url, cancellation: token, progress: { visited in
                        DispatchQueue.main.async {
                            guard let self, self.generation == request else { return }
                            self.statusText = .message("Analizando \(item.name) · \(visited.formatted()) elementos…")
                        }
                    }, counted: accumulate)
                    let measuredTotal = total
                    DispatchQueue.main.async {
                        guard let self, self.generation == request,
                              let index = self.entries.firstIndex(where: { $0.id == item.id }) else { return }
                        self.entries[index].measurement = measurement
                        self.totalBytes = measuredTotal
                    }
                }
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.isScanning = false
                    self.statusText = self.incompleteCount > 0
                        ? .count("scan.partial", self.incompleteCount)
                        : .count("scan.complete", items.count)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.isScanning = false
                    self.error = error.localizedDescription
                    self.statusText = .message("No se pudo leer esta carpeta.")
                }
            }
        }
    }
}
