import SwiftUI

struct AssistantResponseView: View {
    @ObservedObject var assistant: LocalAssistantModel
    @ObservedObject private var activity: AssistantActivityModel
    init(assistant: LocalAssistantModel) { self.assistant = assistant; activity = assistant.activity }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !assistant.response.isEmpty {
                Text(assistant.response).font(SoraTypography.body(14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            AssistantActivityView(steps: activity.steps, contextNotice: assistant.contextNotice, expanded: $activity.expanded)
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
    }
}
