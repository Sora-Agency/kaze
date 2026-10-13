import SwiftUI

struct StorageCard: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            Text(value).font(SoraTypography.body(26, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DashboardView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: CleanerModel
    @ViewState private var displayedFraction = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("Libera espacio")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Elige las cachés que quieres limpiar y deja respirar a tu Mac."))
                        .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
                }
                HStack(spacing: 30) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.06), lineWidth: 14)
                        Circle().trim(from: 0, to: displayedFraction)
                            .stroke(AngularGradient(colors: [SoraPalette.accentHover, SoraPalette.accent], center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Text("\(Int(model.storage.fractionUsed * 100))%")
                                .font(SoraTypography.body(31, weight: .bold))
                            Text(L10n.text("ocupado")).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                        }
                    }.frame(width: 148, height: 148).padding(14)
                        .soraAnimate(displayedFraction)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L10n.text("Almacenamiento del Mac")).font(.title3.weight(.semibold))
                        HStack(spacing: 12) {
                            StorageCard(title: L10n.text("Disponible"), value: ByteCountFormatter.string(fromByteCount: model.storage.free, countStyle: .file), color: SoraPalette.accentHover)
                            StorageCard(title: L10n.text("En uso"), value: ByteCountFormatter.string(fromByteCount: model.storage.used, countStyle: .file), color: SoraPalette.accent)
                            StorageCard(title: L10n.text("Capacidad"), value: ByteCountFormatter.string(fromByteCount: model.storage.total, countStyle: .file), color: .secondary)
                        }
                    }
                }.padding(20).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                Text(L10n.text("QUÉ LIMPIAR")).font(SoraTypography.body(11, weight: .semibold)).foregroundStyle(SoraPalette.secondary)
                VStack(spacing: 12) {
                    category(L10n.text("Cachés cotidianas"), detail: L10n.text("Navegadores, Discord, Slack y Homebrew"), icon: "sparkles", selection: $model.includeGeneralCaches)
                    category(L10n.text("Herramientas de desarrollo"), detail: L10n.text("VS Code, Yarn, pip, CocoaPods, Gradle, npm, pnpm y Xcode"), icon: "hammer", selection: $model.includeDevelopmentCaches)
                    category(L10n.text("Cachés de Docker"), detail: L10n.text("Compilaciones antiguas y objetos dangling"), icon: "box", selection: $model.includeDockerCaches)
                }
                HStack(spacing: 8) {
                    LucideIcon("shield-check").foregroundStyle(SoraPalette.accentHover)
                    Text(L10n.text("La limpieza de cachés conserva tus documentos, proyectos y descargas."))
                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                }
                SoraDivider()
                HStack(spacing: 14) {
                    Button { model.runCleanup() } label: { SoraLabel(L10n.text("Limpiar ahora"), icon: "sparkles").padding(.horizontal, 8) }
                        .buttonStyle(SoraButtonStyle(kind: .primary)).controlSize(.large)
                        .disabled(model.isCleaning || (!model.includeGeneralCaches && !model.includeDevelopmentCaches && !model.includeDockerCaches))
                    if model.isCleaning { SoraSpinner().controlSize(.small) }
                    Text(model.progressMessage).font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary).lineLimit(1)
                    Spacer()
                    Button { model.refreshStorage() } label: { SoraLabel(L10n.text("Actualizar"), icon: "refresh-cw") }
                }
            }.padding(28)
        }.background(SoraPalette.main)
            .onAppear { displayedFraction = model.storage.fractionUsed }
            .onChange(of: model.storage.fractionUsed) { displayedFraction = $0 }
            .soraAnimate(model.isCleaning)
    }

    private func category(_ title: String, detail: String, icon: String, selection: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            LucideIcon(icon, size: 22).foregroundStyle(SoraPalette.accent)
                .frame(width: 44, height: 44).background(SoraPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(SoraTypography.body(14, weight: .semibold))
                Text(detail).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            Toggle(title, isOn: selection).labelsHidden().toggleStyle(SoraSwitchStyle(showsLabel: false)).disabled(model.isCleaning)
        }.padding(16).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
