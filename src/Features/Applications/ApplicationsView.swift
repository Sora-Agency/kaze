import SwiftUI
import AppKit

struct ApplicationsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: CleanerModel
    @ViewState private var searchText = ""

    private var filteredApplications: [InstalledApplication] {
        model.applications.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }.sorted {
            model.dataOrder.sorts(
                FileEntry(url: $0.url.deletingLastPathComponent().appendingPathComponent($0.name), isDirectory: true, isSymbolicLink: false, modified: nil, measurement: DiskMeasurement(bytes: $0.totalBytes)),
                FileEntry(url: $1.url.deletingLastPathComponent().appendingPathComponent($1.name), isDirectory: true, isSymbolicLink: false, modified: nil, measurement: DiskMeasurement(bytes: $1.totalBytes))
            )
        }
    }

    private func applicationHeader(_ application: InstalledApplication, showsDisclosure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if showsDisclosure {
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
                } else {
                    Color.clear.frame(width: 18, height: 36)
                }
            }

            Toggle(L10n.text("Seleccionar \(application.name)"), isOn: Binding(
                get: { model.selectedApplicationIDs.contains(application.id) },
                set: { model.toggleSelection(for: application, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(SoraCheckboxStyle(showsLabel: false))
            .disabled(model.isRemovingApplicationData)

            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.name).fontWeight(.medium)
                Text(application.url.path)
                    .font(SoraTypography.body(12))
                    .foregroundStyle(SoraPalette.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: application.totalBytes, countStyle: .file))
                    .fontWeight(.semibold)
                if application.relatedBytes > 0 {
                    Text(L10n.text("\(ByteCountFormatter.string(fromByteCount: application.relatedBytes, countStyle: .file)) en datos"))
                        .font(SoraTypography.body(12))
                        .foregroundStyle(SoraPalette.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Aplicaciones")).font(SoraTypography.body(28, weight: .bold))
                    Text(L10n.text("Selecciona apps para moverlas a la Papelera junto con sus datos locales conocidos."))
                        .foregroundStyle(SoraPalette.secondary)
                }
                Spacer()
                if model.isScanningApps || model.isRemovingApplicationData { SoraSpinner() }
                Button(L10n.text("Permisos")) { model.openFullDiskAccessSettings() }
                    .help(L10n.text("Necesario para datos protegidos de algunas aplicaciones"))
                Button(L10n.text("Volver a analizar")) { model.scanApplications() }
                    .disabled(model.isScanningApps || model.isRemovingApplicationData)
            }
            .padding(24)

            HStack {
                Text(L10n.text("Apps y datos locales")).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                Spacer()
                SoraSelect(title: L10n.text("Ordenar"), selection: $model.dataOrder,
                           options: [FileOrder.largest, .smallest, .name, .nameDescending],
                           text: { $0.rawValue }).frame(width: 230)
            }.padding(.horizontal, 24).padding(.bottom, 12)

            List(filteredApplications) { application in
                if application.relatedData.isEmpty {
                    applicationHeader(application)
                } else {
                    VStack(spacing: 0) {
                        applicationHeader(application, showsDisclosure: true)
                        if model.expandedApplicationIDs.contains(application.id) {
                            SoraDivider().padding(.leading, 92)
                            ForEach(model.sortedData(application.relatedData)) { item in
                                ApplicationDataTreeNode(
                                    model: model,
                                    application: application,
                                    item: item,
                                    depth: 0
                                )
                                if item.id != application.relatedData.last?.id {
                                    SoraDivider().padding(.leading, 92)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoraPalette.main)
            .searchable(text: $searchText, prompt: L10n.text("Buscar aplicación"))

            SoraDivider()
            VStack(spacing: 10) {
                HStack {
                    Text(L10n.count("selection.data", model.selectedApplicationData.count, arguments: ByteCountFormatter.string(fromByteCount: model.selectedApplicationDataBytes, countStyle: .file)))
                        .foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        model.confirmApplicationDataRemoval()
                    } label: {
                        SoraLabel(L10n.text("Mover datos seleccionados"), icon: "folder-minus")
                    }
                    .disabled(model.selectedApplicationData.isEmpty || model.isScanningApps || model.isRemovingApplicationData)
                }

                HStack {
                    Text(L10n.count("selection.apps", model.selectedApplications.count, arguments: ByteCountFormatter.string(fromByteCount: model.selectedTotalBytes, countStyle: .file)))
                        .foregroundStyle(SoraPalette.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        model.confirmRemoval()
                    } label: {
                        SoraLabel(L10n.text("Desinstalar apps seleccionadas"), icon: "trash")
                    }
                    .disabled(model.selectedApplications.isEmpty || model.isScanningApps || model.isRemovingApplicationData)
                }
            }
            .padding(16)
        }
        .alert(L10n.text("¿Desinstalar las aplicaciones seleccionadas?"), isPresented: $model.showingRemovalConfirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Mover a la Papelera"), role: .destructive) { model.removeSelectedApplications() }
        } message: {
            Text(L10n.text("Se moverán las apps y sus datos locales relacionados a la Papelera. En Docker esto incluye imágenes, contenedores y volúmenes locales. No se vaciará la Papelera."))
        }
        .alert(L10n.text("¿Mover los datos seleccionados a la Papelera?"), isPresented: $model.showingDataRemovalConfirmation) {
            Button(L10n.text("Cancelar"), role: .cancel) {}
            Button(L10n.text("Mover datos"), role: .destructive) { model.removeSelectedApplicationData() }
        } message: {
            Text(L10n.text("Las aplicaciones permanecerán instaladas, pero pueden cerrarse y perder sesiones, configuraciones, descargas locales o bases de datos. Los datos irán a la Papelera y esta no se vaciará automáticamente."))
        }
    }
}
