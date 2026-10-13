import SwiftUI
import AppKit

struct TrashMenuAction: View {
    @EnvironmentObject private var trash: ReviewedTrashModel
    let target: TrashTarget
    var disabled = false
    var body: some View {
        Button(role: .destructive) { trash.request(target) } label: { SoraLabel(L10n.text("Mover a la Papelera"), icon: "folder-minus") }
            .disabled(disabled || trash.busy || trash.pending != nil)
    }
}

private struct ReviewedTrashScope: ViewModifier {
    @StateObject private var trash: ReviewedTrashModel
    var completion: (URL) -> Void
    init(home: URL, journal: OperationJournal, authorization: @escaping (TrashTarget) -> Bool, completion: @escaping (URL) -> Void) {
        _trash = StateObject(wrappedValue: ReviewedTrashModel(service: ReviewedTrashService(home: home), journal: journal, authorization: authorization))
        self.completion = completion
    }
    func body(content: Content) -> some View {
        content.environmentObject(trash)
            .sheet(item: Binding(get: { trash.pending }, set: { if $0 == nil { trash.dismiss() } })) { request in
                ReviewedTrashConfirmation(request: request, trash: trash, completion: completion).id(request.id)
            }
            .alert(L10n.text("No se pudo mover el elemento"), isPresented: Binding(get: { trash.error != nil }, set: { if !$0 { trash.dismissError() } })) {
                Button(L10n.text("Aceptar")) { trash.dismissError() }
            } message: { Text(trash.error ?? "") }
            .overlay(alignment: .bottomTrailing) {
                if trash.busy && trash.pending == nil {
                    HStack { SoraSpinner(); Text(L10n.text("Comprobando el elemento…")) }
                        .font(SoraTypography.body(12)).padding(12).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 10)).padding(18)
                } else if let url = trash.lastMoved {
                    HStack {
                        SoraLabel(L10n.text("Movido a la Papelera: \(url.lastPathComponent)"), icon: "check").foregroundStyle(SoraPalette.success)
                        Button(L10n.text("Aceptar")) { trash.dismissFeedback() }
                    }.font(SoraTypography.body(12)).padding(12).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 10)).padding(18)
                }
            }
    }
}

struct ReviewedTrashConfirmation: View {
    let request: ReviewedTrashRequest
    @ObservedObject var trash: ReviewedTrashModel
    var completion: (URL) -> Void
    @ViewState private var reviewed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SoraLabel(L10n.text(request.target.directory ? "Revisa el contenido de la carpeta" : "¿Mover este archivo a la Papelera?"), icon: "circle-alert")
                .font(SoraTypography.body(20, weight: .semibold))
            Text(request.target.url.lastPathComponent).font(SoraTypography.body(15, weight: .semibold))
            Text(request.target.url.path).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                .lineLimit(3).truncationMode(.middle).textSelection(.enabled).help(request.target.url.path)
            if request.target.directory {
                Text(L10n.text("Revisa que el contenido no incluya archivos importantes. Se moverá la carpeta completa, con todos sus archivos y subcarpetas."))
                Button(L10n.text("Revisar contenido")) {
                    let url = request.target.url.pathExtension.lowercased() == "app" ? request.target.url.appendingPathComponent("Contents") : request.target.url
                    _ = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
                Toggle(L10n.text("He revisado el contenido y quiero mover la carpeta completa."), isOn: $reviewed).toggleStyle(SoraCheckboxStyle()).disabled(trash.busy)
                if request.target.url.pathExtension.lowercased() == "app" {
                    Text(L10n.text("Se moverá solo la app. Sus datos asociados se conservarán; usa Aplicaciones para revisar una desinstalación completa."))
                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                }
            }
            Text(L10n.text("Podrás restaurar el elemento desde Historial. El espacio no se libera hasta vaciar la Papelera y puede seguir retenido por APFS."))
                .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            HStack {
                if trash.busy { SoraSpinner(); Text(L10n.text("Comprobando el contenido…")) }
                Spacer()
                Button(L10n.text(trash.busy ? "Detener" : "Cancelar")) { trash.dismiss() }
                Button(L10n.text("Mover a la Papelera"), role: .destructive) { trash.confirm(contentsReviewed: reviewed, completion: completion) }
                    .disabled(trash.busy || (request.target.directory && !reviewed))
                    .buttonStyle(SoraButtonStyle(kind: .destructive))
            }
        }.font(SoraTypography.body(13)).padding(28).frame(width: 540).background(SoraPalette.main).interactiveDismissDisabled(trash.busy)
    }
}

extension View {
    func reviewedTrashActions(home: URL, journal: OperationJournal = .shared, completion: @escaping (URL) -> Void = { _ in }) -> some View {
        modifier(ReviewedTrashScope(home: home, journal: journal, authorization: { _ in true }, completion: completion))
    }
    func reviewedTrashActions(home: URL, journal: OperationJournal, authorization: @escaping (TrashTarget) -> Bool, completion: @escaping (URL) -> Void) -> some View {
        modifier(ReviewedTrashScope(home: home, journal: journal, authorization: authorization, completion: completion))
    }
}
