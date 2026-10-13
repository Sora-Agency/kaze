import SwiftUI
import AppKit

struct SystemDataView: View {
    @ObservedObject var model: SmartScanModel
    var openExplorer: (URL) -> Void = { _ in }
    @ObservedObject private var language = AppLanguageStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnalysisHeader(title: "System Data", subtitle: "Qué hay detrás de los datos del sistema.", model: model)
            Text(L10n.text("macOS no publica el desglose exacto de su categoría System Data. Este inventario explica las ubicaciones conocidas; los snapshots comparten bloques APFS y no se suman a los archivos."))
                .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).padding(.horizontal, 28).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SystemDataKind.allCases, id: \.self) { kind in
                        VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            LucideIcon(kind == .simulators ? "smartphone" : "hard-drive", size: 22).foregroundStyle(SoraPalette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L10n.string(kind.rawValue)).font(SoraTypography.body(15, weight: .semibold))
                                Text(L10n.text("Lógico: \(formatDiskBytes(model.systemTotals[kind]?.logical ?? 0))"))
                                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                            Text((model.systemTotals[kind]?.partial == true ? "≥ " : "") + formatDiskBytes(model.systemTotals[kind]?.allocated ?? 0)).font(SoraTypography.body(22, weight: .semibold)).monospacedDigit()
                            Text(model.index.files.isEmpty ? L10n.text("Sin analizar") : L10n.text("Recuperable: 0 – \(formatDiskBytes(model.systemPotential[kind] ?? 0))"))
                                .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                            }
                        }
                        ForEach(model.index.systemLocations[kind] ?? [], id: \.self) { node in
                            let url = model.index.files[node].url
                            Button { openExplorer(url) } label: {
                                HStack { Text(url.path).lineLimit(1).truncationMode(.middle); Spacer(); LucideIcon("arrow-up-right", size: 12) }
                            }.font(SoraTypography.body(11)).help(L10n.text("Abrir en Explorador"))
                                .contextMenu {
                                    Button(L10n.text("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    TrashMenuAction(target: TrashTarget(model.index.files[node]), disabled: model.busy)
                                }
                        }
                        }.padding(20).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SoraLabel(L10n.text("Snapshots locales"), icon: "calendar-clock").font(SoraTypography.body(16, weight: .semibold))
                        Text(L10n.string(model.snapshotStatus)).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                        ForEach(model.snapshots, id: \.self) { Text($0).font(SoraTypography.body(11)).textSelection(.enabled) }
                        Text(L10n.text("Los gestiona macOS y Time Machine. No se borran automáticamente ni se promete recuperar su tamaño completo."))
                            .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.muted)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }.padding(.horizontal, 28)
            }
            AnalysisNotice(model: model)
        }.reviewedTrashActions(home: model.home, journal: model.journal) { _ in model.markChanged() }
    }
}
