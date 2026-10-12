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
    @Published private(set) var measuredAt: Date?
    @Published private(set) var showingCached = false
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
    var sharedIndex: StorageIndex?
    private let cache: AnalysisCache
    private let seeded: Bool
    private var snapshots: [String: CachedExplorerFolder] = [:]
    private var cachedRows: [String: [FileEntry]] = [:]
    private var snapshot: CachedExplorerFolder?
    private var monitor: FolderChangeMonitor?
    private var pending = FolderChanges()
    private var awaitingHistory = false
    private var active = false

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         initialEntries: [FileEntry]? = nil, cache: AnalysisCache? = nil) {
        self.cache = cache ?? AnalysisCache(home: home)
        seeded = initialEntries != nil
        classifier = DeletionClassifier(home: home)
        self.folder = URL(fileURLWithPath: canonicalFilePath(folder), isDirectory: true)
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
        let target = URL(fileURLWithPath: canonicalFilePath(url), isDirectory: true)
        if recordHistory && target.path != folder.path { backHistory.append(folder); forwardHistory.removeAll() }
        folder = target
        search = ""
        loadFolder()
    }
    private func loadSharedIndex() -> Bool {
        guard let index = sharedIndex, Date().timeIntervalSince(index.date) < 120,
              let node = index.byPath[canonicalFilePath(folder)], index.files[node].directory,
              !index.files[node].partial, !index.files[node].detailsLimited else { return false }
        isScanning = false; error = nil; hasLoaded = true; cancelled = false
        entries = (index.children[node] ?? []).map { i in
            let file = index.files[i]
            return FileEntry(url: file.url, isDirectory: file.directory, isSymbolicLink: file.symbolicLink,
                modified: file.modified, measurement: DiskMeasurement(bytes: file.allocated, unreadableCount: file.partial ? 1 : 0))
        }
        totalBytes = index.files[node].allocated
        measuredAt = index.date; showingCached = true
        statusText = .message("Tamaños del último Smart Scan. Actualiza para medir cambios recientes.")
        return true
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
    /// Reuse the last folder and the shared index from the very first entry.
    func loadIfNeeded() {
        active = true
        guard !seeded else { return }
        if !hasLoaded || monitor == nil { loadFolder() }
    }
    func suspendMonitoring() {
        active = false
        monitor?.stop(); monitor = nil
        if isScanning { stop() }
    }
    private func resetRequest() -> UUID {
        cancellation.cancel(); cancellation = ScanCancellation(); generation = UUID()
        monitor?.stop(); monitor = nil; pending = FolderChanges(); awaitingHistory = false
        error = nil; cancelled = false; hasLoaded = true
        return generation
    }
    private func display(_ value: CachedExplorerFolder, rows: [FileEntry], cached: Bool) {
        snapshot = value
        if value.entries.count <= 50_000 { snapshots[value.folder.path] = value; cachedRows[value.folder.path] = rows }
        while snapshots.count > 32 || snapshots.values.reduce(0, { $0 + $1.entries.count }) > 50_000 {
            guard let oldest = snapshots.values.min(by: { $0.date < $1.date }) else { break }
            snapshots[oldest.folder.path] = nil; cachedRows[oldest.folder.path] = nil
        }
        entries = rows; totalBytes = value.totalBytes
        measuredAt = value.date; showingCached = cached
    }
    private func loadFolder() {
        let request = resetRequest(), target = folder, token = cancellation, cache = cache
        snapshot = snapshots[target.path]
        if let snapshot, let rows = cachedRows[target.path] { display(snapshot, rows: rows, cached: true) }
        else if !loadSharedIndex() { entries = []; totalBytes = 0; measuredAt = nil; showingCached = false }
        if seeded { if snapshot == nil && !loadSharedIndex() { scan() }; return }
        isScanning = true
        statusText = .message("Comprobando cambios…")
        let memory = snapshot
        let shared = sharedIndex, classifier = classifier
        queue.async { [weak self] in
            var value = memory ?? cache.loadFolder(target)
            if value == nil, let index = shared, Date().timeIntervalSince(index.date) < 120,
               let node = index.byPath[target.path], index.files[node].directory,
               !index.files[node].partial, !index.files[node].detailsLimited {
                let file = index.files[node]
                value = CachedExplorerFolder(schema: 1, folder: target, date: index.date, eventID: index.eventID,
                    volumeID: FolderChangeMonitor.volumeID(file.fingerprint.device), rootFingerprint: file.fingerprint,
                    entries: (index.children[node] ?? []).map { i in
                        let child = index.files[i]
                        return CachedExplorerEntry(url: child.url, directory: child.directory, symbolicLink: child.symbolicLink,
                            modified: child.modified, fingerprint: child.fingerprint,
                            measurement: DiskMeasurement(bytes: child.allocated, unreadableCount: child.partial ? 1 : 0))
                    }, totalBytes: file.allocated, independent: !index.files.contains { !$0.directory && $0.links > 1 })
            }
            let current = DiskScanner.metadata(target)
            let checkpoint = FolderChangeMonitor.eventID()
            let valid = value.map { saved in
                saved.complete && saved.eventID > 0 && saved.eventID <= checkpoint
                    && Date().timeIntervalSince(saved.date) < 86_400
                    && !["/Volumes", "/private/var", "/private/tmp"].contains(where: { pathIsWithin(target.path, root: $0) })
                    && current.map { Int64($0.st_dev) == saved.rootFingerprint.device && UInt64($0.st_ino) == saved.rootFingerprint.inode
                        && FolderChangeMonitor.volumeID(Int64($0.st_dev)) == saved.volumeID && saved.volumeID != nil } == true
            } ?? false
            let rows = value?.entries.map { $0.entry(classifier: classifier) } ?? []
            DispatchQueue.main.async {
                guard let self, self.generation == request, !token.isCancelled else { return }
                if let value { self.display(value, rows: rows, cached: true) }
                self.startMonitor(since: valid ? value!.eventID : checkpoint, request: request)
                if valid && self.monitor != nil { self.awaitingHistory = true }
                else { self.refresh(changes: FolderChanges(full: true), checkpoint: checkpoint) }
            }
        }
    }
    private func startMonitor(since: UInt64, request: UUID) {
        guard !seeded else { return }
        monitor = FolderChangeMonitor(folder: folder, since: since, ignoring: cache.directory) { [weak self] changes in
            guard let self, self.generation == request, !self.cancelled else { return }
            self.pending.merge(changes)
            if self.awaitingHistory && changes.historyDone {
                self.awaitingHistory = false
                let updates = self.pending; self.pending = FolderChanges()
                self.refresh(changes: updates, checkpoint: max(since, updates.eventID))
            } else if !self.isScanning {
                self.scheduleRefresh(request: request)
            }
        }
    }
    private func scheduleRefresh(request: UUID) {
        guard pending.full || !pending.paths.isEmpty else { return }
        // Coalesce bursts without polling. Only one utility scan runs at a time.
        isScanning = true; statusText = .message("Actualizando cambios…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.generation == request, !self.cancelled else { return }
            let changes = self.pending; self.pending = FolderChanges()
            self.refresh(changes: changes, checkpoint: max(self.snapshot?.eventID ?? 0, changes.eventID))
        }
    }
    private func refresh(changes: FolderChanges, checkpoint: UInt64) {
        let request = generation, target = folder, previous = snapshot, token = cancellation
        let classifier = classifier, cache = cache, persist = !seeded
        isScanning = true; statusText = .message(entries.isEmpty ? "Leyendo contenido…" : "Actualizando cambios…")
        queue.async { [weak self] in
            do {
                var lastProgress: UInt64 = 0
                let value = try ExplorerSnapshotBuilder.refresh(folder: target, previous: previous, changes: changes,
                    force: changes.full, checkpoint: checkpoint, cancellation: token, classifier: classifier,
                    listed: { rows, bytes in
                        DispatchQueue.main.async {
                            guard let self, self.generation == request, !token.isCancelled else { return }
                            self.entries = rows; self.totalBytes = bytes
                        }
                    }, progress: { name in
                        let now = DispatchTime.now().uptimeNanoseconds
                        guard now - lastProgress > 100_000_000 else { return }; lastProgress = now
                        DispatchQueue.main.async {
                            guard let self, self.generation == request, !token.isCancelled else { return }
                            self.statusText = .message("Analizando \(name)…")
                        }
                    })
                guard !token.isCancelled else { return }
                let rows = value.entries.map { $0.entry(classifier: classifier) }
                if persist { cache.saveFolder(value) }
                DispatchQueue.main.async {
                    guard let self, self.generation == request, !token.isCancelled else { return }
                    self.display(value, rows: rows, cached: false); self.isScanning = false; self.error = nil
                    self.statusText = self.incompleteCount > 0 ? .count("scan.partial", self.incompleteCount) : .count("scan.complete", value.entries.count)
                    self.scheduleRefresh(request: request)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == request, !token.isCancelled else { return }
                    self.isScanning = false; self.error = error.localizedDescription
                    self.statusText = .message("No se pudo leer esta carpeta.")
                }
            }
        }
    }
    func stop() {
        cancellation.cancel(); generation = UUID(); monitor?.stop(); monitor = nil
        awaitingHistory = false; pending = FolderChanges(); isScanning = false; cancelled = true
        statusText = .message("Análisis detenido. Actualiza para completar los tamaños pendientes.")
    }
    func scan() {
        let request = resetRequest()
        let checkpoint = FolderChangeMonitor.eventID()
        startMonitor(since: checkpoint, request: request)
        refresh(changes: FolderChanges(full: true), checkpoint: checkpoint)
    }
    func invalidate() {
        snapshots = [:]; cachedRows = [:]; snapshot = nil; showingCached = measuredAt != nil
        if active && !seeded { scan() }
    }
}
