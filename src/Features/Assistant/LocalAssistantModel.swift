import Foundation
import Combine
import AppKit

@MainActor
final class LocalAssistantModel: ObservableObject {
    enum Phase { case checking, missing, downloading, ready }
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var progress = 0.0
    @Published private(set) var response = ""
    @Published private(set) var submittedQuestion = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var error: String?
    let downloadBytes: Int64
    private let service: LocalAIService
    private let queue = DispatchQueue(label: "kaze.assistant", qos: .utility)
    private var token = ScanCancellation()
    private var request = UUID()
    private var checked = false
    private var termination: AnyCancellable?

    init(service: LocalAIService = LocalAIService(), initialReady: Bool = false, initialResponse: String = "", initialQuestion: String = "") {
        self.service = service; downloadBytes = service.package.downloadBytes
        if initialReady { phase = .ready; checked = true; response = initialResponse; submittedQuestion = initialQuestion }
        termination = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.cancel() }
    }
    deinit { token.cancel(); service.stopExecution() }

    func checkAvailability() {
        guard !checked else { return }; checked = true
        #if KAZE_PREVIEW
        phase = .missing // Fixture previews never inspect or install real AI files.
        #else
        let service = service, token = token, request = request
        queue.async { [weak self] in
            let result = Result { try service.validate(cancellation: token) }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                switch result {
                case .success(let installed): self.phase = installed ? .ready : .missing
                case .failure(let error): self.phase = .missing; self.error = error.localizedDescription
                }
            }
        }
        #endif
    }

    func install() {
        guard phase == .missing, LocalAIPackage.supported else { return }
        #if KAZE_PREVIEW
        return
        #else
        token.cancel(); token = ScanCancellation(); request = UUID()
        let service = service, token = token, request = request
        phase = .downloading; error = nil; progress = 0
        queue.async { [weak self] in
            var lastUpdate = Date.distantPast
            let result = Result { try service.install(cancellation: token) { fraction in
                guard Date().timeIntervalSince(lastUpdate) >= 0.25 || fraction == 1 else { return }
                lastUpdate = Date()
                DispatchQueue.main.async {
                    guard let self, self.request == request else { return }; self.progress = fraction
                }
            } }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                switch result {
                case .success: self.phase = .ready; self.progress = 1
                case .failure(let error): self.phase = .missing; self.error = error.localizedDescription
                }
            }
        }
        #endif
    }

    func ask(_ question: String, analysis: SmartScanModel) {
        guard phase == .ready, !isGenerating, !analysis.busy,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submittedQuestion = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        response = ""; error = nil
        if analysis.index.files.isEmpty {
            error = nil
            response = L10n.text("Primero ejecuta Smart Scan para obtener recomendaciones sobre tu disco."); return
        }
        if analysis.isStale {
            error = L10n.text("El disco cambió desde este análisis. Vuelve a analizar antes de limpiar."); return
        }
        #if KAZE_PREVIEW
        return
        #else
        let scanDate = analysis.index.date
        let prompt = LocalAssistantPrompt.make(question: submittedQuestion, index: analysis.index, findings: analysis.findings,
            totals: analysis.systemTotals, systemPotential: analysis.systemPotential, potential: analysis.potential,
            stale: analysis.isStale, english: L10n.language == "en")
        token.cancel(); token = ScanCancellation(); request = UUID()
        let service = service, token = token, request = request
        isGenerating = true; error = nil; response = ""
        queue.async { [weak self] in
            let result = Result { try service.answer(prompt: prompt, cancellation: token) }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }; self.isGenerating = false
                switch result {
                case .success(let response):
                    if analysis.index.date == scanDate && !analysis.isStale { self.response = response }
                    else { self.error = L10n.text("El disco cambió desde este análisis. Vuelve a analizar antes de limpiar.") }
                case .failure(let error):
                    self.error = error.localizedDescription
                    if let error = error as? LocalAIError, error == .integrity || error == .notInstalled { self.phase = .missing }
                }
            }
        }
        #endif
    }

    func cancel() {
        token.cancel(); service.stopExecution(); request = UUID()
        if phase == .downloading { phase = .missing; progress = 0 }
        isGenerating = false; error = LocalAIError.cancelled.localizedDescription
    }
}
