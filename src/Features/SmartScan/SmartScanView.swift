import SwiftUI

struct SmartScanView: View {
    @ObservedObject var model: SmartScanModel
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewState private var filter: FindingGroup? = nil
    @ViewState private var confirmation = false
    @ViewState private var visibleLimit = 500
    @ViewState private var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var navigate: (AppSection) -> Void
    private func categoryColor(_ group: FindingGroup) -> Color {
        switch group {
        case .safe: return SoraPalette.success
        case .review: return SoraPalette.color(light: 0xa06a1c, dark: 0xd7b778)
        case .applications: return SoraPalette.color(light: 0x586bb0, dark: 0x9caee2)
        case .duplicates: return SoraPalette.color(light: 0x805bb4, dark: 0xbba4db)
        case .development: return SoraPalette.accent
        }
    }
    var body: some View {
        let counts = model.findings.reduce(into: [FindingGroup: Int]()) { $0[$1.group, default: 0] += 1 }
        let matches = model.findings.filter { filter == nil || $0.group == filter }
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                if !compact {
                    AnalysisHeader(title: "Kaze Smart Scan", subtitle: "Una mirada de conjunto. Tú decides qué limpiar.", model: model)
                        .transition(collapseTransition)
                }
                overview(counts: counts)
            }.background(SoraPalette.main).clipped()
                .animation(reduceMotion ? nil : SoraMotion.collapse, value: compact)
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        if let error = model.error {
                            Text(error).font(SoraTypography.body(12)).foregroundStyle(Color.orange)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                        }
                        if model.index.files.isEmpty {
                            emptyState
                        } else {
                            HStack {
                                Text(L10n.string(filter?.rawValue ?? "Resultados del análisis")).font(SoraTypography.body(13, weight: .semibold))
                                Spacer()
                                Text(String(matches.count)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary).monospacedDigit()
                            }.padding(.horizontal, 24).padding(.vertical, 14)
                            ForEach(Array(matches.prefix(visibleLimit))) { finding in
                                FindingRow(model: model, finding: finding, selectable: finding.rule?.regenerable == true && finding.rule?.projectFolder == nil)
                                SoraDivider().padding(.leading, 24)
                            }
                            if matches.isEmpty {
                                Text(L10n.text("No hay resultados en esta categoría.")).foregroundStyle(SoraPalette.secondary).padding(32)
                            }
                            if matches.count > visibleLimit {
                                Button(L10n.text("Mostrar más resultados")) { visibleLimit += 500 }.padding()
                            }
                        }
                    }
                }.background(SmartScanScrollObserver(compact: $compact).allowsHitTesting(false))
            }
                .onChange(of: filter) { _ in visibleLimit = 500 }
            SoraDivider()
            HStack {
                Text(L10n.text("\(model.index.scannedCount) elementos · selección explícita"))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                Spacer()
                Button(L10n.text("Revisar selección")) { confirmation = true }
                    .disabled(model.selected.isEmpty || model.busy || model.catalog == nil || model.isStale)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.alert(L10n.text("¿Mover la selección a la Papelera?"), isPresented: $confirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Mover a la Papelera"), role: .destructive) { model.removeSelection() }
        } message: { Text(L10n.text("Revisa que el contenido no incluya archivos importantes. Se moverá la carpeta completa, con todos sus archivos y subcarpetas.") + "\n\n" + L10n.text("Se comprobarán otra vez los archivos y los procesos activos. Los elementos que hayan cambiado o estén en uso se conservarán. Podrás restaurarlos desde Historial.")) }
        .reviewedTrashActions(home: model.home, journal: model.journal) { _ in model.markChanged() }
    }
    private var collapseTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: -10))
    }
    private func overview(counts: [FindingGroup: Int]) -> some View {
        VStack(spacing: 0) {
            if compact {
                HStack {
                    Text("Kaze Smart Scan").font(SoraTypography.body(14, weight: .semibold))
                    Spacer()
                    AnalysisActions(model: model)
                }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)
                    .transition(collapseTransition)
            }
            HStack(spacing: 10) {
                summary("Recuperación potencial", "0 – " + formatDiskBytes(model.potential), "Cachés y copias exactas verificadas", accent: true)
                summary("Asignado en disco", formatDiskBytes(model.index.allocated), "APFS · " + L10n.string("Estimación"))
                summary("Espacio para revisar", formatDiskBytes(model.opportunities.reviewBytes), "Requiere revisión manual")
            }.padding(.horizontal, 24).padding(.bottom, compact ? 8 : 12)
            if !compact {
                HStack(spacing: 8) {
                    ForEach(FindingGroup.allCases) { group in
                        category(group, count: group == .duplicates ? model.duplicates.exact.count : counts[group, default: 0])
                    }
                }.padding(.horizontal, 24).transition(collapseTransition)
            }
            AnalysisStatusStrip(model: model)
            SoraDivider()
        }
    }
    private func category(_ group: FindingGroup, count: Int) -> some View {
        Button {
            if group == .duplicates { navigate(.duplicates) }
            else if group == .applications { navigate(.applications) }
            else { filter = filter == group ? nil : group }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 7) {
                    LucideIcon(group.icon, size: 16).foregroundStyle(categoryColor(group))
                    Text(L10n.string(group.rawValue)).font(SoraTypography.body(11, weight: .semibold)).lineLimit(2)
                }.frame(height: 28, alignment: .top)
                Text(String(count)).font(SoraTypography.body(21, weight: .semibold)).monospacedDigit()
                Text(categoryDetail(group))
                    .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).frame(height: 104)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(SoraPalette.surface)
                        RoundedRectangle(cornerRadius: 10).fill(categoryColor(group).opacity(filter == group ? 0.17 : 0.08))
                    }
                }.overlay(RoundedRectangle(cornerRadius: 10).stroke(categoryColor(group).opacity(filter == group ? 0.5 : 0.18)))
        }.buttonStyle(.plain).accessibilityLabel(L10n.string(group.rawValue) + ", " + String(count))
    }
    private func categoryDetail(_ group: FindingGroup) -> String {
        if group == .duplicates { return "0 – " + formatDiskBytes(model.duplicates.exact.reduce(0) { $0 + $1.potential }) }
        if group == .safe { return "0 – " + formatDiskBytes(model.opportunities.potentialByGroup[group, default: 0]) }
        return formatDiskBytes(model.opportunities.allocatedByGroup[group, default: 0]) + " · " + L10n.string("En disco")
    }
    private func summary(_ title: String, _ value: String, _ detail: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            Text(L10n.string(title)).font(SoraTypography.body(compact ? 10 : 11)).foregroundStyle(SoraPalette.secondary)
            Text(value).font(SoraTypography.body(compact ? 18 : 25, weight: .semibold)).monospacedDigit()
                .foregroundStyle(accent ? SoraPalette.accent : SoraPalette.text).lineLimit(1).minimumScaleFactor(0.75)
            if !compact {
                Text(L10n.string(detail)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted).lineLimit(1)
                    .transition(.opacity)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 58 : 94, alignment: .leading)
            .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var emptyState: some View {
        VStack(spacing: 15) {
            LucideIcon("sparkles", size: 44).foregroundStyle(SoraPalette.accent)
            Text(L10n.text("Encuentra oportunidades de limpieza")).font(SoraTypography.body(20, weight: .semibold))
            Text(L10n.text("Un solo análisis alimenta el mapa, los duplicados, System Data y las recomendaciones locales."))
                .foregroundStyle(SoraPalette.secondary).frame(maxWidth: 520).multilineTextAlignment(.center)
            Text(L10n.text("No se elimina nada durante el análisis."))
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
    }
}
