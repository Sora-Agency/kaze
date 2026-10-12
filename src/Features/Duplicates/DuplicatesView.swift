import SwiftUI
import AppKit

struct DuplicatesView: View {
    @ObservedObject var model: SmartScanModel
    @ViewState private var confirmation = false
    @ViewState private var visibleLimit = 200
    @ViewState private var copyLimits: [String: Int] = [:]
    @ViewState private var preview: URL?
    @ObservedObject private var language = AppLanguageStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnalysisHeader(title: "Duplicados", subtitle: "Hashes para copias exactas. Vision para similitudes que debes revisar.", model: model)
            HStack {
                Text(L10n.text("Las primeras copias se conservan. Fotos, respaldos y archivos sincronizados quedan protegidos."))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                Spacer()
                Button(L10n.text("Hashes exhaustivos")) { model.compareExact() }.disabled(model.busy || model.index.files.isEmpty)
                Button(L10n.text("Comparar fotos con Vision")) { model.comparePhotos() }.disabled(model.busy || model.index.files.isEmpty)
            }.padding(.horizontal, 28).padding(.bottom, 16)
            if model.duplicates.partial || model.duplicates.skipped > 0 {
                Text(L10n.text("Cobertura limitada: \(model.duplicates.examined) archivos comparados; \(model.duplicates.skipped) omitidos. Búsqueda rápida de hashes: hasta 8 GiB, 10.000 archivos o 60 s. Vision: hasta 400 fotos de 32 MiB."))
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary).padding(.horizontal, 28).padding(.bottom, 12)
            }
            if model.hashesExhaustive {
                Text(L10n.text("Hashes exhaustivos sobre los candidatos conservados; sin límite de bytes ni tiempo. Vision: \(model.duplicates.visualExamined) fotos comparadas."))
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary).padding(.horizontal, 28).padding(.bottom, 12)
            }
            SoraDivider()
            if model.duplicates.exact.isEmpty && model.duplicates.similar.isEmpty {
                Text(L10n.text("Analiza el Mac o una carpeta para buscar duplicados exactos."))
                    .foregroundStyle(SoraPalette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array((model.duplicates.exact + model.duplicates.similar).prefix(visibleLimit))) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    SoraLabel(L10n.string(group.similar ? "Visualmente similares · revisar" : "Copias exactas · SHA-256"), icon: group.similar ? "circle-alert" : "check")
                                    Spacer()
                                    Text(group.similar ? L10n.string("Sin recuperación automática") : "0 – " + formatDiskBytes(group.potential))
                                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                                }
                                ForEach(Array(group.nodes.prefix(copyLimits[group.id] ?? 100)), id: \.self) { node in
                                    let file = model.index.files[node]
                                    HStack {
                                        if !group.similar && model.canSelectDuplicate(node) {
                                            Toggle("", isOn: Binding(get: { model.duplicateSelection.contains(node) }, set: {
                                                if $0 { model.duplicateSelection.insert(node) } else { model.duplicateSelection.remove(node) }
                                            })).labelsHidden().disabled(model.busy).accessibilityLabel(file.url.path)
                                        } else { LucideIcon("shield-check").foregroundStyle(SoraPalette.success) }
                                        Text(file.url.path).font(SoraTypography.body(12)).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(formatDiskBytes(file.allocated)).font(SoraTypography.body(12)).monospacedDigit()
                                        Button(L10n.text("Quick Look")) { preview = file.url }
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { LucideIcon("arrow-up-right") }.help(L10n.text("Mostrar en Finder"))
                                    }
                                }
                                if group.nodes.count > (copyLimits[group.id] ?? 100) { Button(L10n.text("Mostrar más copias")) { copyLimits[group.id, default: 100] += 100 } }
                            }.padding(18).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if model.duplicates.exact.count + model.duplicates.similar.count > visibleLimit {
                            Button(L10n.text("Mostrar más resultados")) { visibleLimit += 200 }
                        }
                    }.padding(28)
                }
            }
            AnalysisNotice(model: model)
            HStack { Spacer(); Button(L10n.text("Revisar selección")) { confirmation = true }
                .disabled(model.duplicateSelection.isEmpty || model.busy || model.catalog == nil) }.padding(20)
        }.kazeQuickLook($preview)
        .alert(L10n.text("¿Mover los duplicados seleccionados?"), isPresented: $confirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Mover a la Papelera"), role: .destructive) { model.removeSelection(duplicatesOnly: true) }
        } message: { Text(L10n.text("Se recalcularán los hashes de cada copia y del original conservado. Las fotos similares nunca se eliminan automáticamente.")) }
    }
}
