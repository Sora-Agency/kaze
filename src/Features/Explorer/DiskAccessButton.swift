import SwiftUI

struct DiskAccessButton: View {
    @ObservedObject var access: DiskAccessStore
    var action: () -> Void

    private var granted: Bool { access.status == .available }

    var body: some View {
        Button(action: action) {
            LucideIcon(access.status.icon, size: 18)
                .foregroundStyle(granted ? SoraPalette.success : SoraPalette.secondary)
                .frame(width: 36, height: 36)
                .background(granted ? SoraPalette.success.opacity(0.10) : SoraPalette.surface,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(granted ? SoraPalette.success.opacity(0.22) : SoraPalette.borderSoft))
        }
        .buttonStyle(SoraNavigationButtonStyle())
        .help(access.status.description + ". " + L10n.text("Abrir Acceso total al disco en Ajustes del Sistema"))
        .accessibilityLabel(L10n.text("Acceso total al disco"))
        .accessibilityValue(access.status.description)
        .soraAnimate(access.status)
    }
}
