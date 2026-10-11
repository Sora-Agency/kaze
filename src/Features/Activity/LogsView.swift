import SwiftUI

struct LogsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Registro")).font(SoraTypography.body(28, weight: .bold))
                Spacer()
                Button(L10n.text("Mostrar en Finder")) { model.revealLog() }
                Button(L10n.text("Actualizar")) { model.refreshLogs() }
            }

            ScrollView {
                ScrollViewReader { proxy in
                    Text(model.logText.isEmpty ? L10n.text("Todavía no hay registros.") : model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                        .id("log-end")
                        .onChange(of: model.logText) { _ in
                            proxy.scrollTo("log-end", anchor: .bottom)
                        }
                }
            }
            .background(SoraPalette.main, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        }
        .padding(24)
    }
}
