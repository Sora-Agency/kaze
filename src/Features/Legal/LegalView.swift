import SwiftUI
import AppKit

enum LegalDocument: String, CaseIterable, Identifiable {
    case terms = "Términos de uso", privacy = "Privacidad", license = "Licencia MIT"
    var id: String { rawValue }
    var filename: String {
        switch self { case .terms: return "TERMS.txt"; case .privacy: return "PRIVACY.txt"; case .license: return "LICENSE" }
    }
}

struct LegalView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let resourceDirectory: URL?
    @ViewState private var document: LegalDocument = .terms
    @ViewState private var contents = ""
    @ViewState private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Hecho por Sora. Abierto para todos.")).font(SoraTypography.body(27, weight: .semibold))
                    Text(L10n.text("Términos, privacidad y licencia de Kaze.")).foregroundStyle(SoraPalette.secondary)
                }
                Spacer()

            }
            HStack(alignment: .top, spacing: 14) {
                LucideIcon("info").font(.title2).foregroundStyle(SoraPalette.accent)
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("Usa Kaze bajo tu responsabilidad")).font(SoraTypography.body(15, weight: .semibold))
                    Text(L10n.text("El software se ofrece tal cual, sin garantías. Sora Agency y los colaboradores excluyen su responsabilidad por pérdidas de datos y otros daños en la medida permitida por la ley. Las obligaciones y los derechos que la ley no permite excluir siguen vigentes."))
                        .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SoraPalette.borderSoft))
            HStack {
                SoraSegmentedControl(title: L10n.text("Documento"), selection: $document,
                                     options: LegalDocument.allCases, text: { $0.rawValue }).frame(maxWidth: 460)
                Spacer()
                Button { saveCopy() } label: { SoraLabel(L10n.text("Guardar una copia"), icon: "arrow-down-to-line") }
                    .disabled(loadError != nil || contents.isEmpty)
            }
            ScrollView {
                Text(loadError ?? contents)
                    .font(document == .license ? .system(size: 12, design: .monospaced) : SoraTypography.body(14))
                    .lineSpacing(6).textSelection(.enabled)
                    .foregroundStyle(SoraPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SoraPalette.borderSoft))
            HStack {
                Text(L10n.text("Sora Agency · Kaze \(AppIdentity.version) · Documentos del 11 de octubre de 2026"))
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.muted)
                Spacer()
                Link(L10n.text("Sobre la licencia MIT ↗"), destination: URL(string: "https://opensource.org/license/mit")!)
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.accent)
            }
        }.padding(28).background(SoraPalette.main)
            .onAppear(perform: load)
            .onChange(of: document) { _ in load() }
            .onChange(of: language.selection) { _ in load() }
    }

    private func load() {
        guard let directory = resourceDirectory ?? Bundle.main.resourceURL else {
            loadError = L10n.text("No se encontró la documentación incluida con Kaze."); return
        }
        do {
            contents = try String(contentsOf: L10n.document(document.filename, in: directory), encoding: .utf8)
            loadError = nil
        } catch {
            contents = ""
            loadError = L10n.text("No se pudo leer este documento: \(error.localizedDescription)")
        }
    }

    private func saveCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.filename == "LICENSE" ? "Kaze-LICENSE.txt" : "Kaze-" + document.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try contents.write(to: url, atomically: true, encoding: .utf8) }
        catch { loadError = L10n.text("No se pudo guardar la copia: \(error.localizedDescription)") }
    }
}
