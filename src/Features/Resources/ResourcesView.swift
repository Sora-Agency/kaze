import SwiftUI
import AppKit

struct ResourcesView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: CleanerModel
    @ViewState private var showingDataRemovalConfirmation = false

    private var visibleKinds: [ManagedResourceKind] {
        ManagedResourceKind.allCases.filter { kind in
            model.managedResources.contains { $0.kind == kind }
        }
    }

    private func resources(for kind: ManagedResourceKind) -> [ManagedResource] {
        model.managedResources.filter { $0.kind == kind }
    }

    private var applicationsWithData: [InstalledApplication] {
        model.applications.filter { !$0.relatedData.isEmpty }
    }

    private func applicationDataGroup(_ application: InstalledApplication) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.setExpanded(
                        application,
                        expanded: !model.expandedApplicationIDs.contains(application.id)
                    )
                } label: {
                    LucideIcon(model.expandedApplicationIDs.contains(application.id)
                          ? "chevron-down" : "chevron-right")
                        .font(SoraTypography.body(12, weight: .semibold))
                        .frame(width: 18, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.name).fontWeight(.medium)
                    Text(L10n.count("app.dataLocations", application.relatedData.count))
                        .font(SoraTypography.body(12))
                        .foregroundStyle(SoraPalette.secondary)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: application.relatedBytes, countStyle: .file))
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 5)

            if model.expandedApplicationIDs.contains(application.id) {
                SoraDivider().padding(.leading, 74)
                ForEach(model.sortedData(application.relatedData)) { item in
                    ApplicationDataTreeNode(
                        model: model,
                        application: application,
                        item: item,
                        depth: 0
                    )
                    .padding(.leading, 28)

                    if item.id != application.relatedData.last?.id {
                        SoraDivider().padding(.leading, 74)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Recursos")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Administra datos locales de aplicaciones y recursos internos de Docker y Xcode."))
                        .foregroundStyle(SoraPalette.secondary)
                }

                Spacer()

                if model.isScanningResources || model.isRemovingResources {
                    SoraSpinner().controlSize(.small)
                }

                Button(L10n.text("Permisos")) { model.openFullDiskAccessSettings() }
                    .help(L10n.text("Abrir Acceso total al disco en Ajustes del Sistema"))
                Button(L10n.text("Actualizar")) {
                    model.scanApplications()
                    model.refreshResources()
                }
                .disabled(model.isScanningResources || model.isRemovingResources || model.isScanningApps)
                Button {
                    model.refreshResources(startDocker: true)
                } label: {
                    SoraLabel(L10n.text("Abrir Docker y analizar"), icon: "play")
                }
                .disabled(model.isScanningResources || model.isRemovingResources)
            }
            .padding(24)

            HStack(spacing: 12) {
                SoraLabel(L10n.count("apps.withData", applicationsWithData.count), icon: "folder")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1), in: Capsule())
                SoraLabel(model.dockerStatus, icon: "box")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                Text(model.resourceStatus)
                    .foregroundStyle(SoraPalette.secondary)
                Spacer()
                if model.dockerStatus.contains(L10n.text("sin respuesta")) {
                    Button(L10n.text("Reiniciar Docker")) { model.confirmDockerRestart() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            if applicationsWithData.isEmpty && model.managedResources.isEmpty
                && !model.isScanningResources && !model.isScanningApps {
                VStack(spacing: 12) {
                    LucideIcon("circle-question-mark")
                        .font(SoraTypography.body(36))
                        .foregroundStyle(SoraPalette.secondary)
                    Text(L10n.text("No hay recursos para mostrar"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.text("No se detectaron datos locales de apps, Docker ni Xcode."))
                        .foregroundStyle(SoraPalette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !applicationsWithData.isEmpty {
                        Section(L10n.text("Datos de aplicaciones")) {
                            ForEach(applicationsWithData) { application in
                                applicationDataGroup(application)
                            }
                        }
                    }

                    ForEach(visibleKinds, id: \.self) { kind in
                        Section(L10n.string(kind.rawValue)) {
                            ForEach(resources(for: kind)) { resource in
                                HStack(spacing: 12) {
                                    Toggle(L10n.text("Seleccionar \(resource.title)"), isOn: Binding(
                                        get: { model.selectedResourceIDs.contains(resource.id) },
                                        set: { model.toggleResource(resource, selected: $0) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(SoraCheckboxStyle(showsLabel: false))
                                    .disabled(!resource.canSelect || model.isRemovingResources)

                                    LucideIcon(resource.kind.icon)
                                        .font(.title2)
                                        .foregroundStyle(resource.canSelect ? Color.accentColor : Color.secondary)
                                        .frame(width: 34)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(resource.title).fontWeight(.medium)
                                        Text(resource.detail)
                                            .font(SoraTypography.body(12))
                                            .foregroundStyle(SoraPalette.secondary)
                                            .lineLimit(1)
                                        if let reason = resource.blockedReason {
                                            Text(reason)
                                                .font(SoraTypography.body(12))
                                                .foregroundStyle(.orange)
                                        }
                                    }

                                    Spacer()

                                    Text(resource.sizeText)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(resource.sizeBytes > 0 ? Color.primary : Color.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }

            SoraDivider()
            VStack(spacing: 10) {
                HStack {
                    Text(L10n.count("selection.appData", model.selectedApplicationData.count, arguments: ByteCountFormatter.string(fromByteCount: model.selectedApplicationDataBytes, countStyle: .file)))
                        .foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showingDataRemovalConfirmation = true
                    } label: {
                        SoraLabel(L10n.text("Mover datos a la Papelera"), icon: "folder-minus")
                    }
                    .disabled(model.selectedApplicationData.isEmpty || model.isRemovingApplicationData)
                }

                HStack {
                    let measurableCount = model.selectedResources.filter { $0.sizeBytes > 0 }.count
                    Text(L10n.count("selection.resources", model.selectedResources.count, arguments: ByteCountFormatter.string(fromByteCount: model.selectedResourceBytes, countStyle: .file)))
                        .foregroundStyle(SoraPalette.secondary)
                    if model.selectedResources.count > measurableCount {
                        Text(L10n.text("+ tamaño interno de Docker"))
                            .font(SoraTypography.body(12))
                            .foregroundStyle(SoraPalette.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.confirmResourceRemoval()
                    } label: {
                        SoraLabel(L10n.text("Eliminar recursos"), icon: "trash")
                    }
                    .disabled(model.selectedResources.isEmpty || model.isScanningResources || model.isRemovingResources)
                }
            }
            .padding(16)
        }
        .onAppear { if !model.hasLoadedResources { model.refreshResources() } }
        .alert(L10n.text("¿Eliminar permanentemente estos recursos?"), isPresented: $model.showingResourceRemovalConfirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Eliminar definitivamente"), role: .destructive) { model.removeSelectedResources() }
        } message: {
            Text(L10n.text("Se eliminarán \(model.selectedResources.count) recursos seleccionados. No irán a la Papelera. Los contenedores Docker activos se detendrán; los volúmenes pueden contener bases de datos y los simuladores o runtimes deberán descargarse otra vez si vuelves a necesitarlos."))
        }
        .alert(L10n.text("¿Mover los datos seleccionados a la Papelera?"), isPresented: $showingDataRemovalConfirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Mover datos"), role: .destructive) { model.removeSelectedApplicationData() }
        } message: {
            Text(L10n.text("Las apps permanecerán instaladas, pero pueden perder sesiones, configuraciones, descargas locales o bases de datos. La Papelera no se vaciará automáticamente."))
        }
        .alert(L10n.text("¿Reiniciar Docker Desktop?"), isPresented: $model.showingDockerRestartConfirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Reiniciar")) { model.restartDockerDesktop() }
        } message: {
            Text(L10n.text("Docker está abierto, pero su motor no responde. Reiniciarlo detendrá temporalmente los contenedores en ejecución y luego volverá a analizarlos."))
        }
    }
}
