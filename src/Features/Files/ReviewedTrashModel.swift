import Foundation
import Combine

@MainActor
final class ReviewedTrashModel: ObservableObject {
    @Published private(set) var pending: ReviewedTrashRequest?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var lastMoved: URL?
    private let service: ReviewedTrashService
    private let journal: OperationJournal
    private let authorization: (TrashTarget) -> Bool
    private let queue = DispatchQueue(label: "kaze.reviewed-trash", qos: .utility)
    private var cancellation = ScanCancellation()

    init(service: ReviewedTrashService, journal: OperationJournal, authorization: @escaping (TrashTarget) -> Bool = { _ in true }) {
        self.service = service; self.journal = journal; self.authorization = authorization
    }
    deinit { cancellation.cancel() }

    func request(_ target: TrashTarget) {
        guard !busy, pending == nil, authorization(target) else { return }
        busy = true; error = nil; lastMoved = nil
        let service = service
        queue.async { [weak self] in
            let result = Result { try service.prepare(target) }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                switch result {
                case .success(let request):
                    if self.authorization(target) { self.pending = request }
                    else { self.error = AnalysisActionError.changed.localizedDescription }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func confirm(contentsReviewed: Bool, completion: @escaping (URL) -> Void) {
        guard !busy, let request = pending, !request.target.directory || contentsReviewed else { return }
        guard authorization(request.target) else {
            pending = nil; error = AnalysisActionError.changed.localizedDescription; return
        }
        busy = true; cancellation = ScanCancellation()
        let service = service, journal = journal, cancellation = cancellation
        queue.async { [weak self] in
            let result = Result { try service.perform(request, journal: journal, cancellation: cancellation) }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false; self.pending = nil
                switch result {
                case .success: self.lastMoved = request.target.url; completion(request.target.url)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func dismiss() {
        if busy { cancellation.cancel() }
        else { pending = nil }
    }
    func dismissError() { error = nil }
    func dismissFeedback() { lastMoved = nil }
}
