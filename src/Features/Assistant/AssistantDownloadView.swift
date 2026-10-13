import SwiftUI

struct AssistantDownloadView: View {
    @ObservedObject var assistant: LocalAssistantModel
    var navigate: (AppSection) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        LucideIcon("brain-circuit", size: 36).foregroundStyle(SoraPalette.accent)
                            .frame(width: 72, height: 72).background(SoraPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                        Text(L10n.text("Entiende tu espacio.\nDecide con calma."))
                            .font(SoraTypography.body(30, weight: .semibold)).lineSpacing(2)
                        Text(L10n.text("Descarga el motor y el modelo una sola vez. Después puedes consultar sin conexión. Tus preguntas y los datos del análisis se quedan en tu Mac."))
                            .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary).lineSpacing(3)
                        SoraLabel(L10n.text("Solo en tu Mac"), icon: "shield-check").font(SoraTypography.body(11)).foregroundStyle(SoraPalette.success)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    installPanel.frame(width: 260)
                }
                SoraDivider()
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Una ayuda para decidir mejor")).font(SoraTypography.body(16, weight: .semibold))
                    HStack(alignment: .top, spacing: 12) {
                        feature("Entiende System Data", detail: "Ponle contexto a los tamaños medidos.", icon: "hard-drive")
                        feature("Cuida tus proyectos", detail: "Consulta qué se puede reconstruir.", icon: "hammer")
                        feature("Revisa antes de limpiar", detail: "Las reglas verificadas siguen a la vista.", icon: "shield-check")
                    }
                }
                HStack(spacing: 14) {
                    Text(L10n.text("Smart Scan y sus reglas verificadas siguen disponibles sin descargar la IA."))
                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    Button(L10n.text("Abrir Smart Scan")) { navigate(.smart) }
                }
            }.padding(32).frame(maxWidth: 980).padding(.top, 22).frame(maxWidth: .infinity)
        }
    }
    private var installPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SoraLabel(L10n.text("IA local opcional"), icon: "sparkles").font(SoraTypography.body(13, weight: .semibold)).foregroundStyle(SoraPalette.accent)
            Text(formatDiskBytes(assistant.downloadBytes)).font(SoraTypography.body(28, weight: .semibold)).monospacedDigit()
            Text(L10n.text("Una descarga. Sin suscripción.")).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
            if assistant.phase == .removing {
                HStack { SoraSpinner(); Text(L10n.text("Desinstalando la IA local…")) }.font(SoraTypography.body(11))
            } else if assistant.phase == .checking {
                HStack { SoraSpinner(); Text(L10n.text("Comprobando la IA local…")) }.font(SoraTypography.body(11))
            } else if assistant.phase == .downloading {
                ProgressView(value: assistant.progress).tint(SoraPalette.accent)
                HStack {
                    Text(assistant.progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    Spacer(); Button(L10n.text("Cancelar")) { assistant.cancel() }
                }.font(SoraTypography.body(11))
                Text(L10n.text("Descargando y verificando…")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
            } else {
                Button { assistant.install() } label: { SoraLabel(L10n.text("Descargar IA local"), icon: "download") }
                    .buttonStyle(SoraButtonStyle(kind: .primary)).disabled(!LocalAIPackage.supported)
                if !LocalAIPackage.supported { Text(LocalAIError.unsupported.localizedDescription).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary) }
            }
            if let error = assistant.error { Text(error).font(SoraTypography.body(11)).foregroundStyle(Color.orange) }
            Text(L10n.text("La app no instala la IA automáticamente. El motor se inicia solo al consultar y se cierra al terminar."))
                .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
            SoraDivider()
            Link("Qwen3 0.6B · Apache 2.0", destination: LocalAIPackage.modelLicense)
            Link("llama.cpp · MIT", destination: URL(string: "https://github.com/ggml-org/llama.cpp/releases/tag/b10566")!)
        }.font(SoraTypography.body(10)).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SoraPalette.accent.opacity(0.2)))
    }
    private func feature(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LucideIcon(icon, size: 20).foregroundStyle(SoraPalette.accent)
            Text(L10n.string(title)).font(SoraTypography.body(12, weight: .semibold))
            Text(L10n.string(detail)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
