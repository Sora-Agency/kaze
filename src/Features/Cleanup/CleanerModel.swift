import Foundation
import AppKit
import Combine

@MainActor
final class CleanerModel: ObservableObject {
    @Published var storage = StorageSnapshot()
    @Published var dataOrder: FileOrder = .largest
    @Published var isCleaning = false
    @Published var isScanningApps = false
    @Published var progressText = LocalizedText.message("Listo para limpiar")
    @Published var logText = ""
    @Published var applications: [InstalledApplication] = []
    @Published var selectedApplicationIDs: Set<String> = []
    @Published var selectedApplicationDataIDs: Set<String> = []
    @Published var expandedApplicationIDs: Set<String> = []
    @Published var expandedDataItemIDs: Set<String> = []
    @Published var directoryChildren: [String: [ApplicationDataItem]] = [:]
    @Published var loadingDataItemIDs: Set<String> = []
    @Published var directoryLoadErrors: [String: String] = [:]
    @Published var includeGeneralCaches = true
    @Published var includeDevelopmentCaches = true
    @Published var includeDockerCaches = true
    @Published var showingRemovalConfirmation = false
    @Published var showingDataRemovalConfirmation = false
    @Published var isRemovingApplicationData = false
    @Published var managedResources: [ManagedResource] = []
    @Published var selectedResourceIDs: Set<String> = []
    @Published var isScanningResources = false
    @Published var isRemovingResources = false
    @Published var dockerText = LocalizedText.message("Sin analizar")
    @Published var resourceText = LocalizedText.verbatim("")
    @Published var showingResourceRemovalConfirmation = false
    @Published var showingDockerRestartConfirmation = false

    var progressMessage: String { progressText.string }
    var dockerStatus: String { dockerText.string }
    var resourceStatus: String { resourceText.string }

    let fileManager = FileManager.default
    nonisolated let logURL: URL
    private var logTimer: Timer?

    init(scanOnLaunch: Bool = true, initialStorage: StorageSnapshot? = nil, readsLogs: Bool = true, logURL: URL? = nil) {
        self.logURL = logURL ?? CleanerOperations.logURL
        if let initialStorage { storage = initialStorage }
        else { refreshStorage() }
        if readsLogs { refreshLogs() }
        if scanOnLaunch {
            scanApplications()
            refreshResources()
        }
        if readsLogs {
            logTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshLogs() }
            }
        }
    }

    deinit {
        logTimer?.invalidate()
    }

    func refreshStorage() {
        do {
            let values = try fileManager.attributesOfFileSystem(forPath: "/System/Volumes/Data")
            storage = StorageSnapshot(
                total: (values[.systemSize] as? NSNumber)?.int64Value ?? 0,
                free: (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            )
        } catch {
            appendLog(L10n.text("ERROR al medir el disco: \(error.localizedDescription)"))
        }
    }

    func refreshLogs() {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        logText = lines.suffix(350).joined(separator: "\n")

        if isCleaning,
           let progress = lines.reversed().first(where: { $0.contains("[PROGRESS]") }) {
            progressText = .verbatim(String(progress
                .replacingOccurrences(of: "[PROGRESS] ", with: "")
                .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                .dropFirst(2)
                .joined(separator: " ")))
        }
    }

    func runCleanup() {
        guard !isCleaning else { return }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("cleaner.zsh"),
              fileManager.isExecutableFile(atPath: script.path) else {
            appendLog(L10n.text("ERROR: no se encontró el motor de limpieza dentro de la app."))
            return
        }

        var arguments = ["--manual", "--no-dialog"]
        if !includeGeneralCaches { arguments.append("--skip-general") }
        if !includeDevelopmentCaches { arguments.append("--skip-development") }
        if !includeDockerCaches { arguments.append("--skip-docker") }

        isCleaning = true
        progressText = .message("Preparando limpieza…")
        appendLog(L10n.text("Interfaz: inicio manual con categorías seleccionadas."))

        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        environment["KAZE_LANGUAGE"] = L10n.language
        process.environment = environment
        process.executableURL = script
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCleaning = false
                self.progressText = process.terminationStatus == 0
                    ? .message("Limpieza terminada")
                    : .message("La limpieza terminó con errores")
                self.refreshStorage()
                self.refreshLogs()
                self.scanApplications()
            }
        }

        do {
            try process.run()
        } catch {
            isCleaning = false
            progressText = .message("No se pudo iniciar")
            appendLog(L10n.text("ERROR al iniciar la limpieza: \(error.localizedDescription)"))
        }
    }

    func revealLog() {
        try? fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func appendLog(_ message: String) {
        CleanerOperations.writeLog(message, to: logURL)
        refreshLogs()
    }

    nonisolated func appendLogFromBackground(_ message: String) {
        CleanerOperations.writeLog(message, to: logURL)
    }

}
