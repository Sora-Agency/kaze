import SwiftUI
import AppKit

struct AssistantFileActionsView: View {
    @ObservedObject var assistant: LocalAssistantModel
    @ObservedObject var analysis: SmartScanModel
    @EnvironmentObject private var trash: ReviewedTrashModel

    var body: some View {
        Group {
            if !assistant.proposals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SoraLabel(L10n.text("Acciones propuestas"), icon: "folder-minus")
                        .font(SoraTypography.body(13, weight: .semibold))
                    Text(L10n.text("Cada elemento necesita tu confirmación. No se ha movido ningún archivo."))
                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                    ForEach(assistant.proposals) { proposal in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                LucideIcon(proposal.file.directory ? "folder" : "file", size: 20).foregroundStyle(SoraPalette.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(proposal.file.url.lastPathComponent).font(SoraTypography.body(13, weight: .semibold))
                                    Text(proposal.file.url.path).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(proposal.file.url.path)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatDiskBytes(proposal.file.allocated)).font(SoraTypography.body(12)).monospacedDigit()
                                    Text(L10n.text("Asignado en disco")).font(SoraTypography.body(9)).foregroundStyle(SoraPalette.muted)
                                }
                            }
                            if let rule = proposal.rule {
                                Text(L10n.string(rule.reason)).font(SoraTypography.body(11))
                                Text(L10n.string(rule.recovery)).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                                if !rule.closedProcesses.isEmpty {
                                    Text(L10n.text("Cerrar: \(rule.closedProcesses.joined(separator: ", "))"))
                                        .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                                }
                            }
                            if proposal.rule == nil || proposal.rule?.projectFolder != nil {
                                Text(L10n.text("Puede contener archivos importantes o cambios locales. Revisa el contenido antes de autorizar."))
                                    .font(SoraTypography.body(11)).foregroundStyle(Color.orange)
                            }
                            HStack {
                                Button(L10n.text("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([proposal.file.url]) }
                                Spacer()
                                Button(L10n.text("Revisar acción")) { trash.request(proposal.target) }
                                    .buttonStyle(SoraButtonStyle(kind: .primary))
                                    .disabled(trash.busy || trash.pending != nil || !assistant.canReview(proposal.target, analysis: analysis))
                            }
                        }.padding(16).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SoraPalette.borderSoft))
                    }
                    Text(L10n.text("Mover a la Papelera no libera espacio hasta vaciarla. Puedes restaurar desde Historial."))
                        .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted)
                    if assistant.proposals.contains(where: { !assistant.canReview($0.target, analysis: analysis) }) {
                        Text(L10n.text("El contexto cambió. Vuelve a consultar para preparar nuevas acciones."))
                            .font(SoraTypography.body(11)).foregroundStyle(Color.orange)
                    }
                }
            }
        }.onReceive(trash.$pending) { request in
            if let request, assistant.canReview(request.target, analysis: analysis) { assistant.recordReview(request.target) }
        }
    }
}
