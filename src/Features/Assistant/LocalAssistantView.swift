import SwiftUI
import AppKit

struct LocalAssistantView: View {
    @ObservedObject var model: SmartScanModel
    @ObservedObject var assistant: LocalAssistantModel
    @ObservedObject private var chats: AssistantChatModel
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewState private var question = ""
    @ViewState private var confirmUninstall = false
    @ViewState private var showingChats = false
    @FocusState private var inputFocused: Bool
    var navigate: (AppSection) -> Void
    private var canAsk: Bool { assistant.phase == .ready && !assistant.isGenerating && !model.busy && !chats.isLoading }

    init(model: SmartScanModel, assistant: LocalAssistantModel, navigate: @escaping (AppSection) -> Void) {
        self.model = model; self.assistant = assistant; chats = assistant.chats; self.navigate = navigate
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SoraDivider()
            chatNavigation
            SoraDivider()
            if assistant.phase == .ready || !chats.turns.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        conversation
                        composer
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    SoraPalette.borderSoft.frame(width: 1)
                    AssistantContextView(model: model, navigate: navigate).frame(width: 252)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AssistantDownloadView(assistant: assistant, navigate: navigate)
            }
        }.onAppear { assistant.checkAvailability() }
            .reviewedTrashActions(home: model.home, journal: model.journal, authorization: { assistant.canReview($0, analysis: model) }) { url in
                assistant.recordMove(url); model.markChanged()
            }
            .alert(L10n.text("¿Desinstalar la IA local?"), isPresented: $confirmUninstall) {
                Button(L10n.text("Cancelar"), role: .cancel) {}
                Button(L10n.text("Desinstalar IA"), role: .destructive) { assistant.uninstall() }
            } message: {
                Text(L10n.text("Se eliminarán el modelo y el motor descargados por Kaze. Tus análisis, historial y ajustes se conservarán. Puedes volver a descargar la IA cuando quieras."))
            }
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Asistente local")).font(SoraTypography.body(21, weight: .semibold))
                Text(L10n.text("Menos dudas. Más espacio.")).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            if assistant.phase == .ready {
                SoraLabel(L10n.text("IA local lista"), icon: "shield-check")
                    .font(SoraTypography.body(11, weight: .medium)).foregroundStyle(SoraPalette.success)
            }
            if assistant.hasInstallation {
                Button { confirmUninstall = true } label: { SoraLabel(L10n.text("Desinstalar IA"), icon: "trash") }
                    .disabled(assistant.phase == .removing || assistant.phase == .downloading)
            }
            Button { navigate(.smart) } label: { SoraLabel("Smart Scan", icon: "arrow-up-right") }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
    private var chatNavigation: some View {
        HStack(spacing: 12) {
            Text(chats.isLoading ? L10n.text("Cargando chats…") : chats.selected?.title ?? L10n.text("Nuevo chat"))
                .font(SoraTypography.body(11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            if assistant.phase == .downloading {
                SoraSpinner(size: 13)
                Text(assistant.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(SoraTypography.body(11)).monospacedDigit()
                Button(L10n.text("Detener")) { assistant.cancel() }
            }
            if assistant.phase == .missing {
                Button(L10n.text("Descargar IA")) { assistant.install() }.disabled(!LocalAIPackage.supported)
            }
            Button { assistant.newChat(); question = "" } label: { SoraLabel(L10n.text("Nuevo chat"), icon: "plus") }
                .disabled(chats.isLoading || assistant.phase == .removing || assistant.phase == .downloading)
            Button { showingChats = true } label: { SoraLabel(L10n.text("Chats"), icon: "message-square") }
                .disabled(chats.isLoading || assistant.phase == .removing || assistant.phase == .downloading)
                .popover(isPresented: $showingChats) {
                    AssistantChatHistoryView(chats: chats, assistant: assistant) { showingChats = false; question = "" }
                }
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if chats.turns.isEmpty { welcome }
                    else {
                        ForEach(chats.turns) { turn in
                            AssistantTurnView(turn: turn, current: turn.id == assistant.currentTurnID,
                                              assistant: assistant, analysis: model)
                        }
                    }
                    if let error = chats.error {
                        Text(error).font(SoraTypography.body(11)).foregroundStyle(Color.orange)
                    }
                    Color.clear.frame(height: 1).id("assistant-end")
                }.frame(maxWidth: 720).padding(24).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }.onChange(of: assistant.isGenerating) { _ in proxy.scrollTo("assistant-end", anchor: .bottom) }
                .onChange(of: chats.turns.count) { _ in proxy.scrollTo("assistant-end", anchor: .bottom) }
                .onChange(of: chats.archive.selectedID) { _ in proxy.scrollTo("assistant-end", anchor: .bottom) }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            LucideIcon("sparkles", size: 28).foregroundStyle(SoraPalette.accent).padding(.top, 20)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Entiende tu espacio.\nDecide con calma."))
                    .font(SoraTypography.body(29, weight: .semibold)).lineSpacing(2)
                Text(L10n.text("Haz una pregunta sobre tu último análisis. Te ayudo a entender los tamaños, las cachés y qué conviene revisar."))
                    .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary).lineSpacing(3)
            }
            VStack(spacing: 10) {
                suggestion("¿Por qué crece System Data?", detail: "Entiende qué ocupa espacio", icon: "hard-drive")
                suggestion("¿Qué puedo borrar sin romper mis proyectos?", detail: "Revisa dependencias y reconstrucción", icon: "hammer")
            }
            if model.index.files.isEmpty {
                Text(L10n.text("Primero ejecuta Smart Scan para obtener recomendaciones sobre tu disco."))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                Button(L10n.text("Abrir Smart Scan")) { navigate(.smart) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func suggestion(_ text: String, detail: String, icon: String) -> some View {
        Button { send(L10n.string(text)) } label: {
            HStack(spacing: 12) {
                LucideIcon(icon, size: 18).foregroundStyle(SoraPalette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(text)).font(SoraTypography.body(12, weight: .medium)).multilineTextAlignment(.leading)
                    Text(L10n.string(detail)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                }
                Spacer(minLength: 4)
                LucideIcon("arrow-up-right", size: 14).foregroundStyle(SoraPalette.muted)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SoraPalette.borderSoft))
        }.buttonStyle(.plain).disabled(!canAsk)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    LucideIcon("shield-check", size: 12).foregroundStyle(SoraPalette.success)
                    Text(L10n.text("Consulta privada")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    if model.busy { Text(L10n.text("Análisis en curso")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted) }
                }
                HStack(spacing: 10) {
                    TextField(L10n.text("Pregunta sobre tu disco…"), text: $question)
                        .textFieldStyle(.plain).font(SoraTypography.body(13)).focused($inputFocused)
                        .onSubmit { send(question) }.disabled(!canAsk)
                        .frame(minHeight: 32)
                    if assistant.isGenerating {
                        Button { assistant.cancel() } label: { LucideIcon("x", size: 17) }
                            .buttonStyle(SoraButtonStyle(iconOnly: true)).help(L10n.text("Detener")).accessibilityLabel(L10n.text("Detener"))
                    } else {
                        Button { send(question) } label: { LucideIcon("arrow-up", size: 18) }
                            .buttonStyle(SoraButtonStyle(kind: .primary, iconOnly: true))
                            .disabled(!canAsk || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help(L10n.text("Consultar")).accessibilityLabel(L10n.text("Consultar"))
                    }
                }
            }.padding(14).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(inputFocused ? SoraPalette.accent.opacity(0.7) : SoraPalette.border))
            Text(L10n.text("La IA puede equivocarse. Cada acción requiere tu revisión y confirmación; nunca se elimina sin preguntar."))
                .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 18)
    }
    private func send(_ text: String) {
        guard canAsk, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assistant.ask(text, analysis: model); question = ""
    }
}
