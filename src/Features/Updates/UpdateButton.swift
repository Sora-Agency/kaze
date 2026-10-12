import SwiftUI

struct UpdateButton: View {
    #if !KAZE_PREVIEW
    @ObservedObject private var updater = AppUpdater.shared
    private var canCheck: Bool { updater.canCheckForUpdates }
    #else
    private var canCheck: Bool { false }
    #endif

    var body: some View {
        Button {
            #if !KAZE_PREVIEW
            updater.checkForUpdates()
            #endif
        } label: {
            HStack(spacing: 10) {
                LucideIcon("arrow-down-to-line").frame(width: 18).foregroundStyle(SoraPalette.muted)
                Text(L10n.text("Buscar actualizaciones…"))
                    .font(SoraTypography.body(13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SoraPalette.secondary)
            .padding(.horizontal, 12).frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoraNavigationButtonStyle())
        .disabled(!canCheck)
    }
}
