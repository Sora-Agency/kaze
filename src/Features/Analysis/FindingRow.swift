import SwiftUI
import AppKit

struct FindingRow: View {
    @ObservedObject var model: SmartScanModel
    let finding: StorageFinding
    var selectable = false
    var body: some View {
        let file = model.index.files[finding.node]
        HStack(spacing: 12) {
            if selectable {
                Toggle("", isOn: Binding(get: { model.selected.contains(finding.node) }, set: {
                    if $0 { model.selected.insert(finding.node) } else { model.selected.remove(finding.node) }
                })).labelsHidden().disabled(file.partial || file.containsProtected || model.busy || model.isStale)
                    .accessibilityLabel(L10n.text("Seleccionar \(file.url.lastPathComponent)"))
            }
            LucideIcon(finding.group.icon, size: 20).foregroundStyle(finding.rule?.regenerable == true && finding.rule?.projectFolder == nil && !file.partial && !file.containsProtected ? SoraPalette.success : SoraPalette.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.rule.map { L10n.string($0.title) } ?? file.url.lastPathComponent).font(SoraTypography.body(14, weight: .semibold))
                Text(file.url.path).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).lineLimit(1).truncationMode(.middle)
                Text(finding.potential > 0 ? L10n.text("Recuperación estimada: 0 – \(formatDiskBytes(finding.potential))")
                     : file.partial || file.containsProtected ? L10n.text("Sin estimación segura; revisa los detalles") : L10n.text("Revisión manual; no incluido en recuperación potencial"))
                    .font(SoraTypography.body(10)).foregroundStyle(finding.potential > 0 ? SoraPalette.success : SoraPalette.secondary)
                if let rule = finding.rule {
                    Text(L10n.string(rule.recovery)).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                    Text(L10n.text("Cerrar: \(rule.closedProcesses.map { L10n.string($0) }.joined(separator: ", "))"))
                        .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text((file.partial ? "≥ " : "") + formatDiskBytes(file.allocated)).monospacedDigit()
                Text(L10n.text("Modificado: \(L10n.date(file.modified))")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                if model.usageQueried.contains(finding.node) {
                    Text(model.lastUsed[finding.node].map { L10n.text("Uso registrado: \(L10n.date($0))") } ?? L10n.text("Último uso desconocido"))
                        .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                }
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { LucideIcon("arrow-up-right") }
                .help(L10n.text("Mostrar en Finder"))
        }.padding(.horizontal, 28).padding(.vertical, 14)
    }
}
