import SwiftUI

struct RecoverySourceView: View {
    @ObservedObject var model: RecoveryModel
    @ViewState private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LucideIcon(model.imageURL == nil ? "hard-drive" : "file", size: 20).foregroundStyle(SoraPalette.accent)
                if let image = model.imageURL {
                    Text(image.lastPathComponent).lineLimit(1).truncationMode(.middle)
                } else {
                    TextField(L10n.text("Partición APFS · /dev/rdisk4s2"), text: $model.devicePath).disabled(model.busy || model.connected)
                }
                Spacer(minLength: 8)
                if model.connected { Button(L10n.text("Cerrar origen")) { model.disconnect() }.disabled(model.busy) }
                else {
                    if !model.devices.isEmpty {
                        Menu(L10n.text("Discos")) { ForEach(model.devices) { device in Button(device.id + " · " + ByteCountFormatter.string(fromByteCount: device.bytes, countStyle: .file)) { model.useDevice(device.rawPath) } } }.disabled(model.busy)
                    }
                    Button(L10n.text("Detectar discos")) { model.detect() }.disabled(model.busy)
                    Button(L10n.text("Abrir imagen")) { model.chooseImage() }.disabled(model.busy)
                    Button(L10n.text("Abrir origen")) { model.connect() }
                        .buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.busy || (model.imageURL == nil && model.devicePath.isEmpty))
                }
            }
            if model.imageURL != nil && !model.connected {
                DisclosureGroup(L10n.text("Opciones de imagen"), isExpanded: $advanced) {
                    HStack {
                        Text(L10n.text("Desplazamiento APFS en bytes"))
                        TextField("0", text: $model.imageOffset).frame(width: 130).disabled(model.busy)
                        Text(L10n.text("Usa 0 para una imagen del contenedor; indica el inicio de la partición para una imagen completa."))
                            .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                    }.padding(.top, 10)
                }.font(SoraTypography.body(12))
            }
        }.padding(18).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 28).padding(.bottom, 12)
    }
}
