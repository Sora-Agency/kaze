import Foundation
import Combine
import AppKit

@MainActor
final class LocalAssistantModel: ObservableObject {
    enum Phase { case checking, missing, downloading, ready, removing }
    @Published var phase: Phase = .checking
    @Published private(set) var progress = 0.0
    @Published var response = ""
    @Published var submittedQuestion = ""
    @Published var isGenerating = false
    @Published var error: String?
    @Published var contextNotice: String?
    @Published private(set) var hasInstallation = false
    @Published var proposals: [AssistantFileProposal] = []
    let activity = AssistantActivityModel()
    let chats: AssistantChatModel
    var currentTurnID: UUID?
    var reviewContext: (chatID: UUID, turnID: UUID, url: URL)?
    var proposalScanDate: Date?
    var proposalRevision: UUID?
    let downloadBytes: Int64
    let service: LocalAIService
    let queue = DispatchQueue(label: "kaze.assistant", qos: .utility)
    var token = ScanCancellation()
    var request = UUID()
    private var checked = false
    private var termination: AnyCancellable?

    init(service: LocalAIService = LocalAIService(), chatStore: AssistantChatStore? = nil, initialReady: Bool = false, initialResponse: String = "", initialQuestion: String = "") {
        self.service = service; downloadBytes = service.package.downloadBytes
        chats = AssistantChatModel(store: chatStore ?? AssistantChatStore(home: service.home))
        chats.onSelect = { [weak self] turn in self?.restoreConversation(turn) }
        chats.load()
        if initialReady { phase = .ready; checked = true; hasInstallation = true; response = initialResponse; submittedQuestion = initialQuestion }
        termination = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.cancel(); self?.chats.flush() }
    }
    deinit { token.cancel(); service.stopExecution() }

    func checkAvailability() {
        guard !checked else { return }; checked = true
        #if KAZE_PREVIEW
        phase = .missing
        #else
        let service = service, token = token, request = request
        queue.async { [weak self] in
            let result = Result { try service.validate(cancellation: token) }
            let hasInstallation = service.hasInstallation
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                self.hasInstallation = hasInstallation
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
                case .success: self.phase = .ready; self.progress = 1; self.hasInstallation = true
                case .failure(let error): self.phase = .missing; self.error = error.localizedDescription
                }
            }
        }
        #endif
    }

    func uninstall() {
        guard hasInstallation, phase != .checking, phase != .downloading, phase != .removing else { return }
        #if KAZE_PREVIEW
        return
        #else
        token.cancel(); service.stopExecution(); request = UUID()
        let service = service, request = request, previous = phase
        let wasGenerating = isGenerating
        activity.stop(); isGenerating = false; persistConversation(status: wasGenerating ? .cancelled : nil); phase = .removing; error = nil; discardProposals()
        queue.async { [weak self] in
            let result = Result { try service.uninstall() }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }
                switch result {
                case .success:
                    self.phase = .missing; self.hasInstallation = false; self.progress = 0
                    self.response = ""; self.submittedQuestion = ""; self.activity.reset(); self.currentTurnID = nil
                case .failure(let error): self.phase = previous; self.error = error.localizedDescription
                }
            }
        }
        #endif
    }

    func cancel() {
        guard phase != .removing, isGenerating || phase == .downloading else { return }
        token.cancel(); service.stopExecution(); request = UUID()
        activity.stop()
        if phase == .downloading { phase = .missing; progress = 0 }
        isGenerating = false; error = LocalAIError.cancelled.localizedDescription; discardProposals()
        persistConversation(status: .cancelled)
    }

    func canReview(_ target: TrashTarget, analysis: SmartScanModel) -> Bool {
        phase == .ready && !isGenerating && !analysis.busy && analysis.catalog != nil
            && analysis.index.date == proposalScanDate && analysis.revision == proposalRevision
            && proposals.contains { $0.file.url == target.url && $0.file.directory == target.directory
                && $0.file.fingerprint == target.fingerprint && $0.authorizationID == target.authorizationID }
    }

    func discardProposals() { proposals = []; proposalScanDate = nil; proposalRevision = nil }

    func recordReview(_ target: TrashTarget) {
        guard !isGenerating, proposals.contains(where: {
            $0.file.url == target.url && $0.file.fingerprint == target.fingerprint && $0.authorizationID == target.authorizationID
        }) else { return }
        if let chatID = chats.archive.selectedID, let turnID = currentTurnID { reviewContext = (chatID, turnID, target.url) }
        activity.complete(.review, detail: .message("Mostró la ruta y solicitó revisar el elemento antes de autorizar la operación."), paths: [target.url]); persistConversation()
    }

    func recordMove(_ url: URL) {
        let context = reviewContext; reviewContext = nil
        if let context, context.url == url, context.turnID != currentTurnID {
            guard let chat = chats.archive.chats.first(where: { $0.id == context.chatID }),
                  let turn = chat.turns.first(where: { $0.id == context.turnID }) else { return }
            let log = AssistantActivityModel(); log.restore(turn.activity)
            log.complete(.trash, detail: .message("Operación confirmada y registrada en Historial. Puedes restaurar el elemento."), paths: [url])
            chats.capture(turn.id, chatID: chat.id, answer: turn.answer, status: turn.status, steps: log.steps, notice: turn.notice, error: turn.error)
        } else {
            activity.complete(.trash, detail: .message("Operación confirmada y registrada en Historial. Puedes restaurar el elemento."), paths: [url])
            discardProposals(); persistConversation()
        }
    }

    func showContextNotice(_ date: Date) {
        contextNotice = L10n.text("Uso el análisis del \(L10n.date(date, includeTime: true)). Los tamaños pueden haber cambiado; comprobaré cada elemento antes de preparar una acción.")
    }

    #if KAZE_PREVIEW
    func previewFileActions(analysis: SmartScanModel) {
        proposals = Array(AssistantFileProposal.candidates(index: analysis.index, findings: analysis.findings, question: submittedQuestion).prefix(1))
        proposalScanDate = analysis.index.date
        proposalRevision = analysis.revision
    }
    func previewActivity(analysis: SmartScanModel, running: Bool) {
        let question = submittedQuestion, answer = response, proposed = proposals, scanDate = proposalScanDate, revision = proposalRevision
        currentTurnID = chats.begin(question)
        submittedQuestion = question; response = answer
        proposals = proposed; proposalScanDate = scanDate; proposalRevision = revision
        activity.reset()
        activity.complete(.context, detail: .message("Tamaños y categorías medidos por Smart Scan."), snapshotDate: analysis.index.date)
        activity.complete(.files, detail: .message("\(6) ubicaciones comprobadas: \(1) disponibles y \(5) omitidas. Se verificaron ubicación e identidad mediante metadatos."), paths: proposals.map { $0.file.url }, checked: 6)
        activity.start(.response)
        if running { response = ""; isGenerating = true }
        else {
            activity.complete(.response, detail: .message("Preparó la explicación en tu Mac usando el resumen del análisis, sin enviar datos."))
            if !proposals.isEmpty {
                activity.complete(.proposals, detail: .message("Acciones para revisar: \(proposals.count). Ningún archivo se mueve sin tu confirmación."), paths: proposals.map { $0.file.url }, criteria: proposals.compactMap { $0.rule.map { .message(L10n.Message(stringLiteral: $0.reason)) } })
            }
        }
        persistConversation(status: running ? .pending : .completed)
    }
    #endif
}
