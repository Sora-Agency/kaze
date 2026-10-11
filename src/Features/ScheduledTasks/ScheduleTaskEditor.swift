import SwiftUI

struct ScheduleTaskEditor: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: ScheduledTaskModel
    @ViewState private var task: ScheduledCleanupTask
    let isNew: Bool
    let onCancel: () -> Void
    let onSaved: () -> Void
    private let height: CGFloat
    init(model: ScheduledTaskModel, task: ScheduledCleanupTask, isNew: Bool, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void,
         height: CGFloat = 680) {
        self.model = model; _task = ViewState(initialValue: task)
        self.isNew = isNew; self.onCancel = onCancel; self.onSaved = onSaved
        self.height = height
    }
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: task.configuration.hour, minute: task.configuration.minute)) ?? Date()
        }, set: {
            task.configuration.hour = Calendar.current.component(.hour, from: $0)
            task.configuration.minute = Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isNew ? L10n.text("Nueva tarea") : L10n.text("Editar tarea")).font(SoraTypography.body(24, weight: .bold))
                    Text(L10n.text("Elige cuándo y qué limpiar.")).foregroundStyle(SoraPalette.secondary)
                }
                Spacer()
            }.padding(24)
            SoraDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(L10n.text("NOMBRE"))
                        TextField(L10n.text("Nombre de la tarea"), text: $task.name).textFieldStyle(SoraTextFieldStyle())
                    }
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(L10n.text("FRECUENCIA"))
                            SoraSelect(title: L10n.text("Frecuencia"), selection: $task.configuration.frequency,
                                       options: ScheduleFrequency.allCases, text: { $0.rawValue })
                                .frame(width: 210)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(L10n.text("HORA LOCAL"))
                            SoraTimeField(title: L10n.text("Hora de ejecución"), selection: time).frame(width: 140)
                        }
                        if task.configuration.frequency == .weekly {
                            VStack(alignment: .leading, spacing: 10) {
                                fieldLabel(L10n.text("DÍA"))
                                SoraSelect(title: L10n.text("Día de la semana"), selection: $task.configuration.weekday,
                                           options: Array(1...7), text: {
                                    [L10n.text("Domingo"), L10n.text("Lunes"), L10n.text("Martes"), L10n.text("Miércoles"), L10n.text("Jueves"), L10n.text("Viernes"), L10n.text("Sábado")][$0 - 1]
                                }).frame(width: 140)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    SoraDivider()
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel(L10n.text("CONDICIÓN DE ESPACIO"))
                        Toggle(L10n.text("Limpiar solo cuando quede poco espacio"), isOn: $task.configuration.onlyWhenLowSpace).toggleStyle(SoraCheckboxStyle())
                        HStack(spacing: 10) {
                            Text(L10n.text("Menos de")).foregroundStyle(SoraPalette.secondary)
                            TextField(L10n.text("Umbral"), value: $task.configuration.thresholdGiB, formatter: thresholdFormatter)
                                .textFieldStyle(SoraTextFieldStyle()).frame(width: 76)
                            SoraNumberStepper(title: L10n.text("umbral"), value: $task.configuration.thresholdGiB, range: 1...1024)
                            Text(L10n.text("GiB libres")).foregroundStyle(SoraPalette.secondary)
                            Spacer()
                        }.disabled(!task.configuration.onlyWhenLowSpace)
                    }
                    SoraDivider()
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel(L10n.text("QUÉ LIMPIAR"))
                        category(L10n.text("Cachés generales"), detail: L10n.text("Cachés del usuario, Discord y Homebrew."), selection: $task.configuration.generalCaches)
                        category(L10n.text("Cachés de desarrollo"), detail: L10n.text("Xcode, simuladores no disponibles, npm, Gradle, Nx y pnpm."), selection: $task.configuration.developmentCaches)
                        category(L10n.text("Cachés de Docker"), detail: L10n.text("Builds antiguos e imágenes sin referencias; conserva contenedores y volúmenes."), selection: $task.configuration.dockerCaches)
                    }
                    SoraDivider()
                    Toggle(L10n.text("Notificar al terminar"), isOn: $task.configuration.notifications).toggleStyle(SoraCheckboxStyle())
                    Toggle(L10n.text("Activar al guardar"), isOn: $task.configuration.enabled).toggleStyle(SoraSwitchStyle())
                    Text(L10n.text("Guardar una tarea desactivada no programa ninguna limpieza. La hora sigue la zona horaria de tu Mac."))
                        .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(24)
            }.disabled(model.isSaving)
            SoraDivider()
            VStack(alignment: .leading, spacing: 10) {
                if let error = model.error {
                    SoraLabel(error, icon: "circle-alert").foregroundStyle(.red)
                        .font(SoraTypography.body(12)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if model.isSaving { SoraSpinner().controlSize(.small) }
                    Spacer()
                    Button(L10n.text("Cancelar"), action: onCancel)
                        .buttonStyle(SoraButtonStyle(kind: .ghost))
                        .disabled(model.isSaving).keyboardShortcut(.cancelAction)
                    Button {
                        var cleaned = task; cleaned.name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.upsert(cleaned, completion: onSaved)
                    } label: {
                        SoraLabel(isNew ? L10n.text("Crear tarea") : L10n.text("Guardar cambios"), icon: isNew ? "plus" : "check")
                    }.buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.isSaving).keyboardShortcut(.defaultAction)
                }
            }.padding(24)
        }.font(SoraTypography.body(13)).foregroundStyle(SoraPalette.text).tint(SoraPalette.accent)
            .background(SoraPalette.main).frame(width: 740, height: height)
            .buttonStyle(SoraButtonStyle())
            .textFieldStyle(SoraTextFieldStyle())
            .toggleStyle(SoraCheckboxStyle())
            .soraAnimate(task.configuration.frequency)
            .soraAnimate(task.configuration.onlyWhenLowSpace)
            .soraAnimate(model.isSaving)
            .interactiveDismissDisabled(model.isSaving)
    }
    private var thresholdFormatter: NumberFormatter {
        let formatter = NumberFormatter(); formatter.numberStyle = .none; formatter.locale = L10n.locale
        formatter.minimum = 1; formatter.maximum = 1024
        return formatter
    }
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(SoraTypography.body(10, weight: .semibold)).tracking(0.8).foregroundStyle(SoraPalette.muted)
    }
    private func category(_ title: String, detail: String, selection: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: selection).toggleStyle(SoraCheckboxStyle())
            Text(detail).font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 27)
        }
    }
}
