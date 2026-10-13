import Foundation

struct AssistantActivityStep: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case context, files, response, proposals, greeting, missingAnalysis, review, trash }
    enum Status: String, Codable { case running, completed, cancelled, failed }
    var id = UUID()
    let kind: Kind
    var startedAt = Date()
    var finishedAt: Date?
    var status: Status
    var detail: LocalizedText
    var paths: [URL] = []
    var criteria: [LocalizedText] = []
    var checked = 0
    var snapshotDate: Date?

    var duration: TimeInterval? { finishedAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
    var title: String {
        if status == .cancelled { return L10n.string("Actividad detenida") }
        if status == .failed { return L10n.string("No pudo completar este paso") }
        switch kind {
        case .context: return L10n.string("Consultó el análisis guardado")
        case .files: return L10n.string(status == .running ? "Revisando opciones…" : checked > 0 ? "Comprobó los elementos propuestos" : "Revisó las opciones del análisis")
        case .response: return L10n.string(status == .running ? "Preparando respuesta…" : "Respondió en tu Mac")
        case .proposals: return L10n.string("Preparó acciones para tu revisión")
        case .greeting: return L10n.string("Respondió a tu saludo")
        case .missingAnalysis: return L10n.string("Solicitó un análisis del disco")
        case .review: return L10n.string("Solicitó tu confirmación")
        case .trash: return L10n.string("Movió el elemento a la Papelera")
        }
    }
    var icon: String {
        if status == .cancelled { return "x" }
        if status == .failed { return "circle-alert" }
        switch kind {
        case .context, .missingAnalysis: return "hard-drive"
        case .files, .proposals, .review: return "shield-check"
        case .response, .greeting: return "check"
        case .trash: return "folder-minus"
        }
    }
}

struct AssistantFilePlan {
    var candidates: [AssistantFileProposal] = []
    var checked = 0
    var skipped = 0
}
