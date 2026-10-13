import Foundation

@MainActor
extension LocalAssistantModel {
    func persistConversation(status: AssistantChatTurn.Status? = nil) {
        guard let id = currentTurnID else { return }
        let status = status ?? (isGenerating ? .pending : error == nil ? .completed : .failed)
        chats.capture(id, answer: response, status: status, steps: activity.steps, notice: contextNotice, error: error)
    }

    func restoreConversation(_ turn: AssistantChatTurn?) {
        if isGenerating { token.cancel(); service.stopExecution(); request = UUID() }
        isGenerating = false; discardProposals()
        currentTurnID = turn?.id
        submittedQuestion = turn?.question ?? ""; response = turn?.answer ?? ""
        contextNotice = turn?.notice; error = turn?.error
        activity.restore(turn?.activity ?? [])
    }

    func newChat() {
        guard phase != .downloading, phase != .removing else { return }
        if isGenerating { cancel() }
        chats.newChat()
    }
    func selectChat(_ id: UUID) {
        guard phase != .downloading, phase != .removing else { return }
        if isGenerating { cancel() }
        chats.select(id)
    }
    func deleteChat(_ id: UUID) {
        if chats.archive.selectedID == id && isGenerating { cancel() }
        chats.delete(id)
    }
}
