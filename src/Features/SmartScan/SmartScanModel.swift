import Foundation
import AppKit
import Combine

@MainActor
final class SmartScanModel: ObservableObject {
    @Published private(set) var index = StorageIndex.empty
    @Published private(set) var findings: [StorageFinding] = []
    @Published private(set) var duplicates = DuplicateReport()
    @Published private(set) var isScanning = false
    @Published private(set) var isComparing = false
    @Published private(set) var visited = 0
    @Published private(set) var error: String?
    @Published private(set) var isStale = false
    @Published private(set) var showingCached = false
    @Published private(set) var isRestoring = false
    @Published private(set) var hashesExhaustive = false
    @Published private(set) var potential: Int64 = 0
    @Published private(set) var snapshots: [String] = []
    @Published private(set) var snapshotStatus = "Sin analizar"
    @Published private(set) var systemTotals: [SystemDataKind: AnalysisBytes] = [:]
    @Published private(set) var systemPotential: [SystemDataKind: Int64] = [:]
    @Published private(set) var lastUsed: [Int: Date] = [:]
    @Published private(set) var usageQueried: Set<Int> = []
    @Published var selected: Set<Int> = []
    @Published var duplicateSelection: Set<Int> = []
    @Published var isRemoving = false
    let home: URL
    let catalog: RuleCatalog?
    let journal: OperationJournal
    private var token = ScanCancellation()
    private var request = UUID()
    private let queue = DispatchQueue(label: "kaze.analysis", qos: .utility)
    private let cache: AnalysisCache
    private let persists: Bool
    private var restoreAllowed = true
    var onIndex: ((StorageIndex) -> Void)?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, resources: URL? = Bundle.main.resourceURL,
         initialIndex: StorageIndex? = nil, initialDuplicates: DuplicateReport? = nil, journal: OperationJournal? = nil,
         cache: AnalysisCache? = nil) {
        self.home = URL(fileURLWithPath: canonicalFilePath(home), isDirectory: true)
        self.cache = cache ?? AnalysisCache(home: home)
        #if KAZE_PREVIEW
        persists = initialIndex == nil && (cache != nil || home != FileManager.default.homeDirectoryForCurrentUser)
        #else
        persists = initialIndex == nil
        #endif
        self.journal = journal ?? OperationJournal(home: home)
        catalog = resources.flatMap { try? RuleCatalog(directory: $0.appendingPathComponent("Rules")) }
        if let initialIndex { apply(initialIndex) }
        if let initialDuplicates { duplicates = initialDuplicates; potential = Self.estimate(index: index, findings: findings, duplicates: initialDuplicates) }
        if persists { restore() }
    }

    private func restore() {
        let cache = cache, home = home, catalog = catalog
        isRestoring = true
        queue.async { [weak self] in
            let saved = cache.loadAnalysis(home: home)
            let findings = saved.flatMap { catalog?.findings(index: $0.index, home: home) } ?? []
            let totals = saved.map { Self.systemTotals($0.index, home: home) } ?? [:]
            let potential = saved.map { Self.estimate(index: $0.index, findings: findings, duplicates: $0.duplicates) } ?? 0
            DispatchQueue.main.async {
                guard let self, self.restoreAllowed else { return }
                self.isRestoring = false
                guard let saved else { return }
                self.apply(saved.index, prepared: findings, totals: totals)
                self.duplicates = saved.duplicates; self.potential = potential
                self.snapshots = saved.snapshots; self.snapshotStatus = saved.snapshotStatus
                self.isStale = true; self.showingCached = true
            }
        }
    }
    private func persist() {
        guard persists, !isStale, !index.files.isEmpty else { return }
        let value = CachedStorageAnalysis(schema: 1, index: index, duplicates: duplicates,
                                          snapshots: snapshots, snapshotStatus: snapshotStatus)
        let cache = cache
        queue.async { cache.saveAnalysis(value) }
    }

    nonisolated private static func estimate(index: StorageIndex, findings: [StorageFinding], duplicates: DuplicateReport) -> Int64 {
        let covered = findings.filter { $0.potential > 0 }.map { index.files[$0.node].url.path }
        let duplicateBytes = duplicates.exact.flatMap { $0.nodes.dropFirst() }.reduce(Int64(0)) { sum, node in
            let file = index.files[node]
            return sum + (covered.contains { pathIsWithin(file.url.path, root: $0) } ? 0 : file.potentialAllocated)
        }
        return findings.reduce(0) { $0 + $1.potential } + duplicateBytes
    }
    var busy: Bool { isScanning || isComparing || isRemoving }

    private func apply(_ result: StorageIndex, prepared: [StorageFinding]? = nil, totals: [SystemDataKind: AnalysisBytes]? = nil) {
        isStale = false; showingCached = false; hashesExhaustive = false; lastUsed = [:]; usageQueried = []; index = result; findings = prepared ?? catalog?.findings(index: result, home: home) ?? []
        systemTotals = totals ?? Self.systemTotals(result, home: home)
        systemPotential = [:]
        for finding in findings where finding.potential > 0 {
            if let kind = AnalysisProtection.systemKind(result.files[finding.node].url, home: self.home) {
                systemPotential[kind, default: 0] += finding.potential
            }
        }
        potential = Self.estimate(index: result, findings: findings, duplicates: DuplicateReport())
        selected = []; duplicateSelection = []; duplicates = DuplicateReport()
        onIndex?(result)
    }

    nonisolated private static func systemTotals(_ index: StorageIndex, home: URL) -> [SystemDataKind: AnalysisBytes] {
        if !index.systemTotals.isEmpty { return index.systemTotals }
        var result: [SystemDataKind: AnalysisBytes] = [:]
        for file in index.files {
            if let kind = AnalysisProtection.systemKind(file.url, home: home) {
                result[kind, default: AnalysisBytes()].allocated += file.ownAllocated
                result[kind, default: AnalysisBytes()].partial = result[kind, default: AnalysisBytes()].partial || file.partial
                if !file.directory { result[kind, default: AnalysisBytes()].logical += file.logical }
            }
        }
        return result
    }

    #if KAZE_PREVIEW
    func previewScanning(visited: Int) { self.visited = visited; isScanning = true }
    #endif

    func markChanged() {
        restoreAllowed = false; isRestoring = false
        if isScanning || isComparing { token.cancel(); request = UUID(); isScanning = false; isComparing = false }
        if persists { let cache = cache; queue.async { cache.invalidateAnalysis() } }
        guard !index.files.isEmpty else { return }
        isStale = true; selected = []; duplicateSelection = []
    }

    func stop() {
        restoreAllowed = false; isRestoring = false
        token.cancel(); request = UUID(); isScanning = false; isComparing = false
        error = L10n.text("Análisis cancelado; los resultados anteriores se conservan.")
    }

    func scan(roots: [URL]? = nil, includeDuplicates: Bool = true) {
        guard !busy else { return }
        restoreAllowed = false; isRestoring = false
        token.cancel(); let token = ScanCancellation(); self.token = token
        let request = UUID(); self.request = request
        let roots = roots ?? [home, URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Library"), URL(fileURLWithPath: "/private/var")]
        let home = home
        let catalog = catalog
        let includeSnapshots = roots.contains { $0.path == "/private/var" } && home == FileManager.default.homeDirectoryForCurrentUser
        isScanning = true; visited = 0; error = nil
        queue.async { [weak self] in
            let checkpoint = FolderChangeMonitor.eventID()
            var result = StorageIndexer.scan(roots: roots, home: home, cancellation: token) { count in
                DispatchQueue.main.async { guard let self, self.request == request else { return }; self.visited = count }
            }
            result.eventID = checkpoint
            guard !token.isCancelled else { return }
            let findings = catalog?.findings(index: result, home: home) ?? []
            let totals = Self.systemTotals(result, home: home)
            let duplicateResult = includeDuplicates ? DuplicateDetector.exact(index: result, cancellation: token) : DuplicateReport()
            let potential = Self.estimate(index: result, findings: findings, duplicates: duplicateResult)
            guard !token.isCancelled else { return }
            #if KAZE_PREVIEW
            let snapshots = (output: "", status: Int32(1))
            #else
            let snapshots = includeSnapshots ? CleanerOperations.runCommand("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"], timeout: 5) : (output: "", status: Int32(1))
            #endif
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.apply(result, prepared: findings, totals: totals); self.duplicates = duplicateResult; self.visited = result.scannedCount; self.isScanning = false
                self.potential = potential
                self.snapshots = snapshots.status == 0 ? snapshots.output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("com.apple.TimeMachine.") } : []
                self.snapshotStatus = !includeSnapshots ? "Snapshots no consultados en el análisis de una carpeta" : snapshots.status == 0 ? "Inventario de snapshots; tamaño exclusivo no disponible" : "No se pudo consultar Time Machine"
                self.persist()
            }
        }
    }

    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { scan(roots: [url]) }
    }

    func queryUsage() {
        guard !busy, !index.files.isEmpty else { return }
        token.cancel(); let token = ScanCancellation(); self.token = token
        let request = UUID(); self.request = request
        let files = findings.filter { $0.group == .development }.prefix(500).map { ($0.node, index.files[$0.node].url) }
        isComparing = true; visited = 0; error = nil
        queue.async { [weak self] in
            let result = SpotlightUsage.dates(for: files, cancellation: token) { count in
                DispatchQueue.main.async { guard let self, self.request == request else { return }; self.visited = count }
            }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.lastUsed = result.dates; self.usageQueried = result.queried; self.isComparing = false
            }
        }
    }

    func comparePhotos() {
        guard !busy, !index.files.isEmpty else { return }
        token.cancel(); let token = ScanCancellation(); self.token = token
        let request = UUID(); self.request = request; let index = index
        isComparing = true; error = nil; visited = 0
        queue.async { [weak self] in
            let result = DuplicateDetector.similar(index: index, cancellation: token) { count in
                DispatchQueue.main.async { guard let self, self.request == request else { return }; self.visited = count }
            }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.duplicates.visualExamined = result.examined; self.duplicates.similar = result.similar; self.duplicates.skipped += result.skipped
                self.duplicates.partial = self.duplicates.partial || result.partial; self.isComparing = false
                self.persist()
            }
        }
    }

    func compareExact() {
        guard !busy, !index.files.isEmpty else { return }
        token.cancel(); let token = ScanCancellation(); self.token = token
        duplicateSelection = []
        let request = UUID(); self.request = request; let index = index; let findings = findings
        isComparing = true; visited = 0; error = nil
        queue.async { [weak self] in
            let result = DuplicateDetector.exact(index: index, cancellation: token, exhaustive: true) { count in
                DispatchQueue.main.async { guard let self, self.request == request else { return }; self.visited = count }
            }
            let estimate = Self.estimate(index: index, findings: findings, duplicates: result)
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.hashesExhaustive = true; self.duplicates.exact = result.exact; self.duplicates.partial = result.partial
                self.duplicates.examined = result.examined; self.duplicates.skipped = result.skipped
                self.potential = estimate; self.isComparing = false
                self.persist()
            }
        }
    }

    func canSelectDuplicate(_ node: Int) -> Bool {
        !isStale && index.files.indices.contains(node) && duplicates.exact.contains { $0.nodes.dropFirst().contains(node) }
            && !index.files[node].protected && index.files[node].links == 1
            && DuplicateDetector.eligible(index.files[node], index: index)
    }

    func removeSelection(duplicatesOnly: Bool = false) {
        guard !busy, !isStale, catalog != nil else { return }
        if duplicatesOnly { do { try catalog!.authorizeNative("duplicates") } catch { self.error = error.localizedDescription; return } }
        let selected = duplicatesOnly ? duplicateSelection : selected
        let index = index; let findings = findings; let groups = duplicates.exact
        let journal = journal; let version = catalog!.manifest.version
        guard !selected.isEmpty else { return }
        isRemoving = true; error = nil
        queue.async { [weak self] in
            let failures = AnalysisRemoval.trashSelection(nodes: selected, index: index, findings: findings,
                groups: groups, duplicatesOnly: duplicatesOnly, journal: journal, ruleVersion: version)
            DispatchQueue.main.async {
                guard let self else { return }; self.isRemoving = false; self.selected = []; self.duplicateSelection = []
                self.error = failures.isEmpty ? L10n.text("Elementos movidos a la Papelera. Actualiza el análisis.") : failures.joined(separator: "\n")
                // Invalidated sizes are never presented as fresh analysis after a mutation.
                self.findings = []; self.duplicates = DuplicateReport(); self.index = .empty; self.potential = 0; self.systemTotals = [:]; self.systemPotential = [:]; self.onIndex?(.empty)
                self.markChanged()
            }
        }
    }
}
