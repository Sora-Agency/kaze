import Foundation
import Combine

@MainActor
final class AssistantChatModel: ObservableObject {
    @Published private(set) var archive = AssistantChatArchive()
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    var onSelect: ((AssistantChatTurn?) -> Void)?
    private let store: AssistantChatStore
    private let queue = DispatchQueue(label: "kaze.assistant.chats", qos: .utility)
    private var writable = true
    private var revision = UUID()
    var selected: AssistantChat? { archive.chats.first { $0.id == archive.selectedID } }
    var turns: [AssistantChatTurn] { selected?.turns ?? [] }

    init(store: AssistantChatStore) { self.store = store }
    func flush() { queue.sync {} }

    func load() {
        #if !KAZE_PREVIEW
        isLoading = true
        let store = store, revision = revision
        queue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                guard let self, self.revision == revision else { return }
                self.isLoading = false
                switch result {
                case .success(let archive): self.archive = archive; self.onSelect?(self.turns.last)
                case .failure: self.writable = false; self.error = L10n.text("No se pudo leer el historial de chats. El archivo se conserva sin modificar.")
                }
            }
        }
        #endif
    }

    func newChat() {
        guard !isLoading else { return }
        if let empty = archive.chats.first(where: { $0.turns.isEmpty }) {
            archive.selectedID = empty.id; onSelect?(nil); persist(); return
        }
        let chat = AssistantChat()
        archive.chats.insert(chat, at: 0); archive.selectedID = chat.id
        archive = archive.bounded(); onSelect?(nil); persist()
    }
    func select(_ id: UUID) {
        guard !isLoading, archive.chats.contains(where: { $0.id == id }) else { return }
        archive.selectedID = id; onSelect?(turns.last); persist()
    }
    func delete(_ id: UUID) {
        archive.chats.removeAll { $0.id == id }
        if archive.selectedID == id { archive.selectedID = archive.chats.first?.id; onSelect?(turns.last) }
        persist()
    }
    func begin(_ question: String) -> UUID {
        if selected == nil { newChat() }
        let turn = AssistantChatTurn(question: question)
        if let c = archive.chats.firstIndex(where: { $0.id == archive.selectedID }) {
            if archive.chats[c].name.isEmpty { archive.chats[c].name = String(question.prefix(120)) }
            archive.chats[c].turns.append(turn); archive.chats[c].updated = Date()
            archive = archive.bounded(); persist()
        }
        return turn.id
    }
    func capture(_ id: UUID, chatID: UUID? = nil, answer: String, status: AssistantChatTurn.Status,
                 steps: [AssistantActivityStep], notice: String?, error: String?) {
        guard let c = archive.chats.firstIndex(where: { $0.id == (chatID ?? archive.selectedID) }),
              let t = archive.chats[c].turns.firstIndex(where: { $0.id == id }) else { return }
        var next = archive
        next.chats[c].turns[t].answer = answer; next.chats[c].turns[t].status = status
        next.chats[c].turns[t].activity = steps; next.chats[c].turns[t].notice = notice
        next.chats[c].turns[t].error = error; next.chats[c].updated = Date()
        archive = next.bounded(); persist()
    }

    private func persist() {
        guard writable else { return }
        #if !KAZE_PREVIEW
        let archive = archive, store = store
        revision = UUID(); let revision = revision
        queue.async { [weak self] in
            let result = Result { try store.save(archive) }
            DispatchQueue.main.async {
                guard let self, self.revision == revision else { return }
                switch result {
                case .success: self.error = nil
                case .failure: self.error = L10n.text("No se pudo guardar el chat. La conversación sigue disponible en esta sesión.")
                }
            }
        }
        #endif
    }
}
