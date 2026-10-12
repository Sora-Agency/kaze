import SwiftUI

struct AssistantContextView: View {
    @ObservedObject var model: SmartScanModel
    @ViewState private var groups: [AssistantRecommendation] = []
    @ViewState private var details = false
    var navigate: (AppSection) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Tu análisis")).font(SoraTypography.body(13, weight: .semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Recuperación potencial")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                    Text("0 – " + formatDiskBytes(model.potential)).font(SoraTypography.body(23, weight: .semibold)).foregroundStyle(SoraPalette.accent).monospacedDigit()
                    Text(L10n.text("Sin prometer bytes retenidos por APFS")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                    if !model.index.files.isEmpty { Text(L10n.date(model.index.date, includeTime: true)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary) }
                    if model.index.partial || model.isStale || model.catalog == nil {
                        SoraLabel(L10n.string(model.isStale ? "Vuelve a analizar" : model.catalog == nil ? "Firma no verificada" : "Análisis parcial"), icon: "circle-alert")
                            .font(SoraTypography.body(10)).foregroundStyle(Color.orange)
                    }
                    Button { details = true } label: { SoraLabel(L10n.text("Detalles del análisis"), icon: "info") }
                        .buttonStyle(.plain).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                        .accessibilityLabel(L10n.text("Detalles del análisis"))
                        .popover(isPresented: $details) { AnalysisNotice(model: model).frame(width: 510).padding(.vertical, 8) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                SoraLabel(L10n.text("Recomendaciones verificadas"), icon: "shield-check")
                    .font(SoraTypography.body(11, weight: .medium)).foregroundStyle(SoraPalette.success)
                if groups.isEmpty {
                    Text(L10n.text("Las recomendaciones aparecerán después del análisis."))
                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                }
                ForEach(groups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string(group.rule.reason))
                            Text(L10n.string(group.rule.recovery)).foregroundStyle(SoraPalette.secondary)
                            Text(L10n.text("Cerrar: \(group.rule.closedProcesses.map { L10n.string($0) }.joined(separator: ", "))"))
                                .foregroundStyle(SoraPalette.secondary)
                            if group.rule.projectFolder != nil || !group.rule.regenerable {
                                Text(L10n.text("Revisión manual: conserva cambios locales y verifica la receta de reconstrucción.")).foregroundStyle(Color.orange)
                            }
                        }.font(SoraTypography.body(11)).padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.string(group.rule.title)).font(SoraTypography.body(12, weight: .medium))
                            Text(L10n.count("assistant.items", group.count)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                            if group.potential > 0 {
                                Text("0 – " + formatDiskBytes(group.potential)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.success)
                            } else { Text(L10n.text("Revisión manual")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted) }
                        }
                    }.padding(13).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                Button(L10n.text("Revisar en Smart Scan")) { navigate(.smart) }
            }.padding(18)
        }.frame(maxHeight: .infinity).background(SoraPalette.sidebar)
            .onReceive(model.$findings) { groups = Array(AssistantRecommendation.grouped($0).prefix(6)) }
    }
}
