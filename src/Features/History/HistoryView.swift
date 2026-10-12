import SwiftUI
import AppKit

struct HistoryView: View {
    @StateObject private var model: HistoryModel
    init(journal: OperationJournal = .shared) { _model = StateObject(wrappedValue: HistoryModel(journal: journal)) }
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewState private var restoring: OperationRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("Historial y deshacer")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Cada operación, su resultado y las opciones de recuperación."))
                        .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
                }
                Spacer()
                Button(L10n.text("Actualizar")) { model.refresh() }.disabled(model.busy)
            }.padding(28)
            if let error = model.error { Text(error).foregroundStyle(Color.orange).padding(.horizontal, 28) }
            if model.records.isEmpty {
                Text(L10n.text("Las operaciones nuevas aparecerán aquí. Los logs anteriores siguen en Actividad."))
                    .foregroundStyle(SoraPalette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.records) { record in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(L10n.string(record.title)).font(SoraTypography.body(14, weight: .semibold))
                                    Text(L10n.date(record.date, includeTime: true)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                                    Spacer()
                                    Text(L10n.string(status(record.status))).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                                    if record.restorable { Button(L10n.text("Restaurar")) { restoring = record }.disabled(model.busy) }
                                }
                                Text(record.originalPath).font(SoraTypography.body(12)).textSelection(.enabled)
                                Text(L10n.text("Afectado: \(record.allocatedBytes.map(formatDiskBytes) ?? L10n.text("No verificable")) · liberado confirmado: \(record.freedBytes.map(formatDiskBytes) ?? L10n.text("No verificable"))"))
                                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                                if let delta = record.observedFreeDelta {
                                    Text(L10n.text("Cambio observado en espacio libre: \(formatDiskBytes(delta)); puede incluir otras operaciones de macOS."))
                                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.muted)
                                }
                                Text(L10n.string(record.detail)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.muted).textSelection(.enabled)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if model.records.count >= model.limit {
                            Button(L10n.text("Cargar operaciones anteriores")) { model.loadMore() }.disabled(model.busy)
                        }
                    }.padding(28)
                }
            }
        }.onAppear { model.refresh() }
            .alert(L10n.text("¿Restaurar en la ubicación original?"), isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                Button(L10n.text("Cancelar"), role: .cancel) { restoring = nil }
                Button(L10n.text("Restaurar")) { if let record = restoring { model.restore(record) }; restoring = nil }
            } message: { Text(L10n.text("No se sobrescribe ningún archivo. Si el elemento cambió, falta en la Papelera o la carpeta original ya no existe, la restauración se detiene.")) }
    }
    private func status(_ value: String) -> String {
        switch value { case "trashed": return "En Papelera"; case "restored": return "Restaurado"; case "completed": return "Completado · sin deshacer"
        case "failed": return "Error"; default: return "Pendiente de verificar" }
    }
}
