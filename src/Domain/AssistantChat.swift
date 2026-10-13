import Foundation

struct AssistantChatTurn: Codable, Identifiable {
    enum Status: String, Codable { case pending, completed, cancelled, failed }
    var id = UUID()
    var date = Date()
    var question: String
    var answer = ""
    var status: Status = .pending
    var activity: [AssistantActivityStep] = []
    var notice: String?
    var error: String?
}

struct AssistantChat: Codable, Identifiable {
    var id = UUID()
    var created = Date()
    var updated = Date()
    var name = ""
    var turns: [AssistantChatTurn] = []
    var title: String { name.isEmpty ? turns.first?.question ?? L10n.string("Nuevo chat") : name }
}

struct AssistantChatArchive: Codable {
    var version = 1
    var selectedID: UUID?
    var chats: [AssistantChat] = []
    static let chatLimit = 30
    static let turnLimit = 40

    func bounded(interrupted: Bool = false) -> Self {
        var copy = self
        copy.chats = Array(chats.sorted { $0.updated > $1.updated }.prefix(Self.chatLimit))
        for c in copy.chats.indices {
            copy.chats[c].name = String(copy.chats[c].name.prefix(120))
            copy.chats[c].turns = Array(copy.chats[c].turns.suffix(Self.turnLimit))
            for t in copy.chats[c].turns.indices {
                var turn = copy.chats[c].turns[t]
                turn.question = String(turn.question.prefix(1000)); turn.answer = String(turn.answer.prefix(8000))
                turn.activity = Array(turn.activity.suffix(12))
                turn.notice = turn.notice.map { String($0.prefix(2000)) }; turn.error = turn.error.map { String($0.prefix(2000)) }
                if interrupted && turn.status == .pending { turn.status = .cancelled }
                for s in turn.activity.indices {
                    turn.activity[s].paths = Array(turn.activity[s].paths.prefix(6))
                    turn.activity[s].criteria = Array(turn.activity[s].criteria.prefix(3))
                    if interrupted && turn.activity[s].status == .running {
                        turn.activity[s].status = .cancelled; turn.activity[s].finishedAt = copy.chats[c].updated
                    }
                }
                copy.chats[c].turns[t] = turn
            }
        }
        if !copy.chats.contains(where: { $0.id == copy.selectedID }) { copy.selectedID = copy.chats.first?.id }
        return copy
    }
}
