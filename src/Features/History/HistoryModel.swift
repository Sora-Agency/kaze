import Foundation
import Combine

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var records: [OperationRecord] = []
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    private(set) var limit = 500
    private let journal: OperationJournal
    private var listener: AnyCancellable?
    init(journal: OperationJournal = .shared) {
        self.journal = journal
        listener = OperationEvents.updates
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func loadMore() {
        guard !busy else { return }; limit += 500; refresh()
    }
    func refresh() {
        guard !busy else { return }; busy = true
        let journal = journal; let limit = limit
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try journal.records(limit: limit) }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                switch result { case .success(let records): self.records = records
                case .failure(let error): self.error = error.localizedDescription }
            }
        }
    }
    func restore(_ record: OperationRecord) {
        guard !busy else { return }; busy = true; let journal = journal
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try journal.restore(record) }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                if case .failure(let error) = result { self.error = error.localizedDescription }
                else { self.error = nil }
                self.refresh()
            }
        }
    }
}
