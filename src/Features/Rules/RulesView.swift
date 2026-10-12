import SwiftUI

struct RulesView: View {
    @ObservedObject var model: SmartScanModel
    @ObservedObject private var language = AppLanguageStore.shared
    @AppStorage("kaze.monitor.enabled") private var monitorEnabled = true
    @AppStorage("kaze.monitor.alerts") private var monitorAlerts = false
    @ViewState private var showRules = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("Ajustes y seguridad")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Personaliza Kaze y consulta cómo protege tus archivos."))
                        .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
                }
                settingsCard {
                    SoraLabel(L10n.text("Barra de menús y alertas"), icon: "hard-drive")
                        .font(SoraTypography.body(16, weight: .semibold))
                    Toggle(L10n.text("Monitor ligero en la barra de menús"), isOn: $monitorEnabled)
                        .toggleStyle(SoraSwitchStyle())
                    Text(L10n.text("Muestra el espacio disponible y accesos rápidos en la barra de menús."))
                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                    SoraDivider().padding(.vertical, 2)
                    Toggle(L10n.text("Notificar si quedan menos de 20 GB libres"), isOn: $monitorAlerts)
                        .toggleStyle(SoraSwitchStyle()).disabled(!monitorEnabled)
                    Text(L10n.text("Las alertas son opcionales y requieren permiso de macOS. Como máximo se envía una cada seis horas."))
                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                }
                settingsCard {
                    if let catalog = model.catalog {
                        SoraLabel(L10n.text("Protección de limpieza activa"), icon: "shield-check")
                            .font(SoraTypography.body(16, weight: .semibold)).foregroundStyle(SoraPalette.success)
                        Text(L10n.text("Kaze verifica qué puede limpiar y vuelve a comprobar los archivos antes de borrarlos."))
                            .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                        SoraDivider().padding(.vertical, 2)
                        DisclosureGroup(isExpanded: $showRules) {
                            VStack(alignment: .leading, spacing: 16) {
                                SoraLabel(L10n.text("Firma Ed25519 verificada · reglas v\(catalog.manifest.version)"), icon: "shield-check")
                                    .foregroundStyle(SoraPalette.success)
                                Text("SHA-256: " + catalog.digest).font(SoraTypography.body(10)).textSelection(.enabled)
                                Text(L10n.text("Las reglas se distribuyen con la app firmadas por Kaze. No ejecutan comandos arbitrarios ni se actualizan por separado sin verificación."))
                                    .foregroundStyle(SoraPalette.secondary)
                                ForEach(catalog.manifest.rules) { rule in
                                    DisclosureGroup {
                                        ruleDetails(rule)
                                    } label: {
                                        Text(L10n.string(rule.title)).font(SoraTypography.body(12, weight: .medium))
                                    }.padding(14).background(SoraPalette.elevated, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }.font(SoraTypography.body(12)).padding(.top, 16)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text("Detalles de las reglas de limpieza")).font(SoraTypography.body(12, weight: .medium))
                                Text(L10n.text("Información avanzada sobre alcance y recuperación."))
                                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                            }
                        }.soraAnimate(showRules)
                    } else {
                        SoraLabel(L10n.text("No se pudo verificar la firma de las reglas. La limpieza está bloqueada."), icon: "shield-alert")
                            .foregroundStyle(Color.orange)
                    }
                }
            }.padding(28).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private func ruleDetails(_ rule: CleanupRule) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(rule.id).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
            Text(L10n.string(rule.reason))
            Text(L10n.string(rule.recovery)).foregroundStyle(SoraPalette.secondary)
            Text(L10n.text("Cerrar: \(rule.closedProcesses.map { L10n.string($0) }.joined(separator: ", "))"))
            if let project = rule.projectFolder {
                Text(project + " · " + (rule.manifests ?? []).joined(separator: ", ")).textSelection(.enabled)
            } else { Text(rule.paths.joined(separator: "\n")).textSelection(.enabled) }
            if let commands = rule.commands {
                Text(commands.map { $0.joined(separator: " ") }.joined(separator: "\n")).textSelection(.enabled)
            }
        }.font(SoraTypography.body(12)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
    }
}
