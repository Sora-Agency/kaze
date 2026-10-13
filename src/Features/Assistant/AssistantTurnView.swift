import SwiftUI

struct AssistantTurnView: View {
    let turn: AssistantChatTurn
    let current: Bool
    @ObservedObject var assistant: LocalAssistantModel
    @ObservedObject var analysis: SmartScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 7) {
                    Text(L10n.date(turn.date, includeTime: true)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                    Text(turn.question).font(SoraTypography.body(14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .padding(16).background(SoraPalette.elevated, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if current {
                AssistantResponseView(assistant: assistant)
                AssistantFileActionsView(assistant: assistant, analysis: analysis)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !turn.answer.isEmpty {
                        Text(turn.answer).font(SoraTypography.body(14)).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    AssistantActivityView(steps: turn.activity, contextNotice: turn.notice)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = current ? assistant.error : turn.error {
                SoraLabel(error, icon: "circle-alert").font(SoraTypography.body(12)).foregroundStyle(Color.orange)
            } else if turn.status == .cancelled && turn.answer.isEmpty {
                Text(L10n.text("Esta consulta se interrumpió. Puedes volver a preguntar."))
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
