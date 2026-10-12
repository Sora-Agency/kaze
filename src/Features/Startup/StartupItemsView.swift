import SwiftUI
import ServiceManagement

struct StartupItemsView: View {
    @ObservedObject var model: StartupItemsModel
    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 10) {
                SoraLabel(L10n.text("Tú decides qué se abre al iniciar sesión."), icon: "shield-check")
                    .foregroundStyle(SoraPalette.accent)
                Spacer()
                Button(L10n.text("Ajustes de macOS")) { SMAppService.openSystemSettingsLoginItems() }
            }.padding(18).background(SoraPalette.accent.opacity(0.07)).padding(.horizontal, 28)
            if let error = model.error {
                Text(error).foregroundStyle(SoraPalette.danger).textSelection(.enabled).padding(20)
            }
            if !model.loaded { welcome }
            else if model.items.isEmpty {
                Spacer(); Text(L10n.text("No hay apps configuradas para abrirse al iniciar sesión.")).foregroundStyle(SoraPalette.secondary); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in row(item); SoraDivider() }
                    }.padding(.horizontal, 28).padding(.top, 14)
                }
            }
            SoraDivider()
            Text(L10n.text("Las apps desactivadas aquí pueden habilitarse de nuevo. Los servicios en segundo plano se administran en Ajustes de macOS."))
                .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("Apps al inicio")).font(SoraTypography.body(28, weight: .bold))
                Text(L10n.text("Un inicio más tranquilo para tu Mac.")).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            if model.busy { SoraSpinner() }
            Button { model.chooseApplication() } label: { SoraLabel(L10n.text("Añadir app"), icon: "plus") }.disabled(model.busy)
            Button { model.refresh() } label: { SoraLabel(L10n.text(model.loaded ? "Actualizar" : "Cargar apps"), icon: "refresh-cw") }
                .buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.busy)
        }.padding(28)
    }
    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            LucideIcon("play", size: 42).foregroundStyle(SoraPalette.accent)
            Text(L10n.text("Elige cómo empieza tu día.")).font(SoraTypography.body(24, weight: .bold))
            Text(L10n.text("Carga tus apps de inicio. macOS puede pedir permiso para que Kaze controle Eventos del Sistema."))
                .foregroundStyle(SoraPalette.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Button(L10n.text("Cargar apps")) { model.refresh() }.buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.busy)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 14) {
            LucideIcon("layout-grid", size: 22).foregroundStyle(item.enabled ? SoraPalette.accent : SoraPalette.muted)
                .frame(width: 44, height: 44).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(SoraTypography.body(14, weight: .semibold))
                Text(item.path).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(L10n.text(item.enabled ? "Activada" : "Desactivada")).foregroundStyle(item.enabled ? SoraPalette.success : SoraPalette.muted)
            Toggle(L10n.text("Abrir al iniciar sesión"), isOn: Binding(get: { item.enabled }, set: { model.set(item, enabled: $0) }))
                .labelsHidden().toggleStyle(SoraSwitchStyle(showsLabel: false)).disabled(model.busy || !item.isApplication)
        }.padding(.vertical, 16)
    }
}
