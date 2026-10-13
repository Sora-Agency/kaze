import Foundation
import Combine

@MainActor
final class AssistantActivityModel: ObservableObject {
    @Published private(set) var steps: [AssistantActivityStep] = []
    @Published var expanded = false

    static func summary(_ steps: [AssistantActivityStep]) -> String {
        if let running = steps.last(where: { $0.status == .running }) { return running.title }
        if let last = steps.last, last.status != .completed || [.greeting, .missingAnalysis, .review, .trash].contains(last.kind) { return last.title }
        if steps.contains(where: { $0.kind == .files && $0.checked > 0 }) { return L10n.string("Consultó el análisis guardado, comprobó elementos y respondió en tu Mac") }
        return L10n.string("Consultó el análisis guardado y respondió en tu Mac")
    }

    func reset() { steps = []; expanded = false }
    func restore(_ saved: [AssistantActivityStep]) { steps = saved; expanded = false }
    func start(_ kind: AssistantActivityStep.Kind, detail: LocalizedText = .verbatim("")) {
        steps.append(AssistantActivityStep(kind: kind, status: .running, detail: detail))
        if steps.count > 12 { steps.removeFirst(steps.count - 12) }
    }
    func complete(_ kind: AssistantActivityStep.Kind, detail: LocalizedText? = nil, paths: [URL] = [], criteria: [LocalizedText] = [], checked: Int = 0, snapshotDate: Date? = nil) {
        if let index = steps.lastIndex(where: { $0.kind == kind && $0.status == .running }) {
            steps[index].status = .completed; steps[index].finishedAt = Date()
            if let detail { steps[index].detail = detail }
            steps[index].paths = Array(paths.prefix(6)); steps[index].criteria = Array(criteria.prefix(3))
            steps[index].checked = checked
            steps[index].snapshotDate = snapshotDate
        } else {
            start(kind, detail: detail ?? .verbatim("")); complete(kind, paths: paths, criteria: criteria, checked: checked, snapshotDate: snapshotDate)
        }
    }
    func stop(error: String? = nil) {
        for index in steps.indices where steps[index].status == .running {
            steps[index].status = error == nil ? .cancelled : .failed
            steps[index].finishedAt = Date()
            if let error { steps[index].detail = .verbatim(error) }
        }
    }
}
