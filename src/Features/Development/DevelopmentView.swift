import SwiftUI

struct DevelopmentView: View {
    @ObservedObject var analysis: SmartScanModel
    @ObservedObject var cleaner: CleanerModel
    @ViewState private var managed = false
    @ViewState private var visibleLimit = 500
    @ObservedObject private var language = AppLanguageStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(L10n.text("Proyectos y herramientas")) { managed = false }
                Button(L10n.text("Docker y simuladores")) { managed = true }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 16)
            if managed { ResourcesView(model: cleaner) }
            else {
                AnalysisHeader(title: "Developer Mode", subtitle: "Dependencias, cachés y modelos locales, con su coste de reconstrucción.", model: analysis)
                HStack {
                    Button(L10n.text("Consultar último uso")) { analysis.queryUsage() }.disabled(analysis.busy || analysis.index.files.isEmpty)
                    Text(L10n.text("Spotlight puede registrar el último uso. Si no hay datos, se indica como desconocido."))
                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                }.padding(.horizontal, 28).padding(.bottom, 12)
                Text(L10n.text("La fecha indica la última modificación; no garantiza el último uso. Los almacenes compartidos, entornos y modelos requieren revisión."))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).padding(.horizontal, 28).padding(.bottom, 12)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(analysis.findings.filter { $0.group == .development }.prefix(visibleLimit))) { finding in
                            FindingRow(model: analysis, finding: finding)
                            SoraDivider().padding(.horizontal, 28)
                        }
                        if analysis.findings.filter({ $0.group == .development }).count > visibleLimit {
                            Button(L10n.text("Mostrar más resultados")) { visibleLimit += 500 }.padding()
                        }
                    }
                }
                AnalysisNotice(model: analysis)
            }
        }.reviewedTrashActions(home: analysis.home, journal: analysis.journal) { _ in analysis.markChanged() }
    }
}
