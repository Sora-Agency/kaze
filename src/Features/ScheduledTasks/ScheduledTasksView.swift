import SwiftUI

struct ScheduledTasksView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: ScheduledTaskModel
    @ViewState private var editor: ScheduledCleanupTask?
    @ViewState private var deleting: ScheduledCleanupTask?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("Tareas programadas")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Cada limpieza, con su propio horario y categorías.")).foregroundStyle(SoraPalette.secondary)
                }
                Spacer()
                Button { model.error = nil; editor = ScheduledCleanupTask() } label: {
                    SoraLabel(L10n.text("Nueva tarea"), icon: "plus")
                }.buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.isSaving || !model.canManage)
            }.padding(28)
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.tasks.isEmpty {
                        VStack(spacing: 12) {
                            LucideIcon("calendar-plus", size: 32).foregroundStyle(SoraPalette.accent)
                            Text(L10n.text("Todavía no hay tareas")).font(SoraTypography.body(18, weight: .semibold))
                            Text(L10n.text("Crea una limpieza y elige cuándo y qué limpiar.")).foregroundStyle(SoraPalette.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 70)
                    }
                    ForEach(model.tasks) { task in
                        taskCard(task).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }.padding(.horizontal, 28).padding(.bottom, 24)
                HStack(alignment: .top, spacing: 10) {
                    LucideIcon("info").foregroundStyle(SoraPalette.accent)
                    Text(L10n.text("Las tareas nuevas empiezan desactivadas. Funcionan con tu sesión iniciada aunque Kaze esté cerrada. Si coinciden, las limpiezas esperan su turno. Usan sus propias categorías y no borran los documentos del explorador."))
                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 28).padding(.bottom, 28)
            }
            SoraDivider()
            VStack(alignment: .leading, spacing: 10) {
                if let error = model.error {
                    SoraLabel(error, icon: "circle-alert").foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(L10n.count("count.tasks", model.tasks.count) + " · " + L10n.count("count.active", model.registeredIDs.count))
                        .foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    if model.isSaving { SoraSpinner().controlSize(.small); Text(L10n.text("Guardando…")) }
                }
            }.font(SoraTypography.body(12)).padding(.horizontal, 28).padding(.vertical, 16)
        }.background(SoraPalette.main)
            .buttonStyle(SoraButtonStyle())
            .soraAnimate(model.tasks)
            .soraAnimate(model.isSaving)
            .onAppear { model.refreshStatus() }
            .sheet(item: $editor) { task in
                ScheduleTaskEditor(model: model, task: task, isNew: !model.tasks.contains { $0.id == task.id },
                                   onCancel: { editor = nil }, onSaved: { editor = nil })
            }
            .alert(L10n.text("Eliminar tarea"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { task in
                Button(L10n.text("Cancelar"), role: .cancel) { deleting = nil }
                Button(L10n.text("Eliminar"), role: .destructive) { model.delete(task.id); deleting = nil }
            } message: { task in
                Text(L10n.text("Se eliminará «\(task.name)» y su programación. Tus archivos y las otras tareas se conservarán."))
            }
    }
    private func taskCard(_ task: ScheduledCleanupTask) -> some View {
        let active = model.isEnabled(task)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LucideIcon("calendar-clock", size: 22).foregroundStyle(SoraPalette.accent)
                    .frame(width: 42, height: 42)
                    .background(SoraPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.name).font(SoraTypography.body(17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(task.cadence).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                }
                Spacer(minLength: 12)
                Text(active ? L10n.text("Activa") : task.configuration.enabled ? L10n.text("Sin registrar") : L10n.text("Desactivada"))
                    .font(SoraTypography.body(12)).foregroundStyle(active ? SoraPalette.accent : SoraPalette.secondary)
                Toggle(L10n.text("Activar \(task.name)"), isOn: Binding(get: { active }, set: { model.setEnabled(task.id, $0) }))
                    .labelsHidden().toggleStyle(SoraSwitchStyle(showsLabel: false)).fixedSize()
            }
            SoraDivider()
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SoraLabel(task.categories, icon: "sparkles")
                    Text(task.configuration.onlyWhenLowSpace ? L10n.text("Solo con menos de \(task.configuration.thresholdGiB) GiB libres") : L10n.text("Limpiar independientemente del espacio libre"))
                    if active, let next = task.configuration.nextRun() {
                        Text(L10n.text("Próxima programación: \(L10n.date(next, includeTime: true))"))
                    }
                }.font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button { model.error = nil; editor = task } label: { SoraLabel(L10n.text("Editar"), icon: "pencil") }
                        .buttonStyle(SoraButtonStyle()).fixedSize()
                        .accessibilityLabel(L10n.text("Editar \(task.name)"))
                    Button { deleting = task } label: { LucideIcon("trash") }
                        .buttonStyle(SoraButtonStyle(kind: .destructive, iconOnly: true))
                        .help(L10n.text("Eliminar tarea")).accessibilityLabel(L10n.text("Eliminar \(task.name)"))
                }
            }
        }.padding(20).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SoraPalette.borderSoft))
            .disabled(model.isSaving || !model.canManage)
            .soraAnimate(active)
    }
}
