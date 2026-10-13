import SwiftUI

struct AssistantChatHistoryView: View {
    @ObservedObject var chats: AssistantChatModel
    @ObservedObject var assistant: LocalAssistantModel
    var close: () -> Void
    @ViewState private var deleting: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("Chats guardados")).font(SoraTypography.body(14, weight: .semibold))
                Spacer()
                Button { assistant.newChat(); close() } label: { LucideIcon("plus", size: 16) }
                    .help(L10n.text("Nuevo chat")).accessibilityLabel(L10n.text("Nuevo chat"))
            }
            if chats.archive.chats.isEmpty {
                Text(L10n.text("Tus conversaciones se guardarán solo en este Mac."))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(chats.archive.chats) { chat in
                            Button { assistant.selectChat(chat.id); close() } label: {
                                HStack(spacing: 10) {
                                    LucideIcon("message-square", size: 15).foregroundStyle(chat.id == chats.archive.selectedID ? SoraPalette.accent : SoraPalette.muted)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(chat.title).font(SoraTypography.body(12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(L10n.date(chat.updated, includeTime: true)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                                    }
                                    Spacer(minLength: 4)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(chat.id == chats.archive.selectedID ? SoraPalette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).contextMenu {
                                Button(L10n.text("Eliminar chat"), role: .destructive) { deleting = chat.id }
                            }
                        }
                    }
                }
            }
            Text(L10n.text("Hasta 30 chats y 40 consultas por chat. El contexto se conserva dentro de cada conversación."))
                .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(width: 320, height: 390)
            .alert(L10n.text("¿Eliminar este chat?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(L10n.text("Cancelar"), role: .cancel) { deleting = nil }
                Button(L10n.text("Eliminar chat"), role: .destructive) {
                    if let id = deleting { assistant.deleteChat(id) }; deleting = nil
                }
            } message: { Text(L10n.text("Se borrará esta conversación. Las operaciones de archivos seguirán registradas en Historial.")) }
    }
}
