import SwiftUI
import AppKit

struct RecoveryView: View {
    @ObservedObject var model: RecoveryModel
    var body: some View {
        VStack(spacing: 0) {
            header
            RecoverySourceView(model: model)
            if model.connected { browser }
            else { welcome }
            SoraDivider()
            footer
        }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("Recuperación")).font(SoraTypography.body(28, weight: .bold))
                Text(L10n.text("Rescata tus archivos. Dale otra oportunidad a tu disco.")).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            SoraLabel(L10n.text("Origen en solo lectura"), icon: "shield-check").foregroundStyle(SoraPalette.success)
            if model.busy { SoraSpinner(); Button(L10n.text("Detener")) { model.stop() } }
        }.padding(28)
    }
    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: { LucideIcon("chevron-left") }.disabled(model.busy || model.currentPath == "/")
                Text(model.currentPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Text(model.entries.count.formatted()).foregroundStyle(SoraPalette.secondary)
                if model.volumes.count > 1 {
                    SoraSelect(title: L10n.text("Volumen"), selection: Binding(get: { model.selectedVolume ?? 0 }, set: { model.connect(volumeID: $0) }),
                               options: model.volumes.map(\.id), text: { id in model.volumes.first { $0.id == id }?.name ?? "" }).frame(width: 180).disabled(model.busy)
                }
            }.padding(.horizontal, 28).padding(.vertical, 14)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.entries, id: \.name) { entry in row(entry); SoraDivider() }
                }.padding(.horizontal, 28)
            }
        }
    }
    private func row(_ entry: APFSEntry) -> some View {
        HStack(spacing: 14) {
            Toggle(entry.name, isOn: Binding(get: { model.selectedNames.contains(entry.name) }, set: { selected in
                if selected { model.selectedNames.insert(entry.name) } else { model.selectedNames.remove(entry.name) }
            })).labelsHidden().toggleStyle(SoraCheckboxStyle(showsLabel: false)).disabled(model.busy || entry.kind == "other")
            LucideIcon(entry.kind == "dir" ? "folder" : "file", size: 22).foregroundStyle(SoraPalette.accent)
            Text(entry.name).font(SoraTypography.body(14, weight: .medium)).lineLimit(1)
            Spacer()
            if entry.kind == "file" {
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.size), countStyle: .file)).foregroundStyle(SoraPalette.secondary)
            }
            if entry.kind == "dir" { Button { model.enter(entry) } label: { LucideIcon("chevron-right") }.disabled(model.busy) }
        }.padding(.vertical, 14).contentShape(Rectangle()).onTapGesture(count: 2) { model.enter(entry) }
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LucideIcon("hard-drive", size: 46).foregroundStyle(SoraPalette.accent)
                Text(L10n.text("Lo importante merece volver.")).font(SoraTypography.body(26, weight: .bold))
                Text(L10n.text("Explora y copia archivos de un volumen APFS sin cifrar, aunque algunas ramas estén dañadas. Basado en LibreRescateNativo."))
                    .foregroundStyle(SoraPalette.secondary)
                HStack(alignment: .top, spacing: 16) {
                    step("1", "Elige el origen", "Disco externo o imagen APFS sin comprimir.")
                    step("2", "Explora tus archivos", "Marca archivos o carpetas para recuperar.")
                    step("3", "Guarda en otro disco", "Una carpeta nueva y un informe de resultados.")
                }
                Text(L10n.text("No busca archivos borrados, no repara ni formatea. Los volúmenes cifrados, sellados y algunos tipos de compresión no están soportados."))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(number).font(SoraTypography.body(20, weight: .bold)).foregroundStyle(SoraPalette.accent)
            Text(L10n.string(title)).font(SoraTypography.body(14, weight: .semibold))
            Text(L10n.string(detail)).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
            .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status.string).font(SoraTypography.body(12)).textSelection(.enabled)
                if let result = model.outcome {
                    Button(L10n.text("Ver archivos e informe")) { NSWorkspace.shared.open(result.folder) }.buttonStyle(.plain).foregroundStyle(SoraPalette.accent)
                }
            }
            Spacer()
            Button { model.recover() } label: { SoraLabel(L10n.text("Recuperar selección"), icon: "download") }
                .buttonStyle(SoraButtonStyle(kind: .primary)).disabled(!model.connected || model.busy || model.selectedNames.isEmpty)
        }.padding(20)
    }
}
