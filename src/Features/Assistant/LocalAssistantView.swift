import SwiftUI
import AppKit

struct LocalAssistantView: View {
    @ObservedObject var model: SmartScanModel
    @ObservedObject var assistant: LocalAssistantModel
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewState private var question = ""
    @FocusState private var inputFocused: Bool
    var navigate: (AppSection) -> Void
    private var canAsk: Bool { assistant.phase == .ready && !assistant.isGenerating && !model.busy }

    var body: some View {
        VStack(spacing: 0) {
            header
            SoraDivider()
            if assistant.phase == .ready {
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
    }
    private var header: some View {
        HStack(spacing: 12) {
            LucideIcon("brain-circuit", size: 23).foregroundStyle(SoraPalette.accent)
                .frame(width: 44, height: 44).background(SoraPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Asistente local")).font(SoraTypography.body(21, weight: .semibold))
                Text(L10n.text("Menos dudas. Más espacio.")).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            if assistant.phase == .ready {
                SoraLabel(L10n.text("IA local lista"), icon: "shield-check")
                    .font(SoraTypography.body(11, weight: .medium)).foregroundStyle(SoraPalette.success)
            }
            Button { navigate(.smart) } label: { SoraLabel("Smart Scan", icon: "arrow-up-right") }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if assistant.response.isEmpty && !assistant.isGenerating && assistant.submittedQuestion.isEmpty {
                        welcome
                    } else {
                        if !assistant.submittedQuestion.isEmpty {
                            HStack {
                                Spacer(minLength: 48)
                                VStack(alignment: .trailing, spacing: 7) {
                                    Text(L10n.text("Tu consulta")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                                    Text(assistant.submittedQuestion).font(SoraTypography.body(14)).textSelection(.enabled)
                                        .padding(16).background(SoraPalette.elevated, in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                        if assistant.isGenerating || !assistant.response.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 9) {
                                    LucideIcon("brain-circuit", size: 18).foregroundStyle(SoraPalette.accent)
                                    Text("Kaze").font(SoraTypography.body(13, weight: .semibold))
                                    Text(L10n.text("Solo en tu Mac")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                                }
                                if assistant.isGenerating {
                                    HStack(spacing: 10) { SoraSpinner(size: 16); Text(L10n.text("Preparando una respuesta en tu Mac…")) }
                                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).padding(.vertical, 12)
                                } else {
                                    Text(assistant.response).font(SoraTypography.body(14)).lineSpacing(5).textSelection(.enabled)
                                }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(SoraPalette.accent.opacity(0.16)))
                        }
                    }
                    if let error = assistant.error {
                        SoraLabel(error, icon: "circle-alert").font(SoraTypography.body(12)).foregroundStyle(Color.orange)
                    }
                    Color.clear.frame(height: 1).id("assistant-end")
                }.frame(maxWidth: 720).padding(24).frame(maxWidth: .infinity)
            }.onChange(of: assistant.isGenerating) { _ in proxy.scrollTo("assistant-end", anchor: .bottom) }
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
                        .onSubmit { send(question) }.disabled(assistant.isGenerating)
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
            Text(L10n.text("La IA puede equivocarse. Tú revisas y decides; Kaze no limpia desde el chat."))
                .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 18)
    }
    private func send(_ text: String) {
        guard canAsk, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assistant.ask(text, analysis: model); question = ""
    }
}
