import SwiftUI
import AppKit

struct ExplorerView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var explorer: FileExplorerModel
    @ObservedObject var cleaner: CleanerModel
    @ObservedObject var diskAccess: DiskAccessStore
    @ViewState private var pathText = ""
    @ViewState private var editingPath = false

    private var summary: String {
        if explorer.error != nil { return L10n.text("No disponible") }
        let value = ByteCountFormatter.string(fromByteCount: explorer.totalBytes, countStyle: .file)
        return (explorer.isScanning || explorer.incompleteCount > 0 || explorer.cancelled ? "≥ " : "") + value
    }

    var body: some View {
        let visible = explorer.visibleEntries
        let largestSize = visible.compactMap { $0.measurement?.bytes }.max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            header
            navigation
            filters
            deletionFilters
            SoraDivider()
            HStack {
                Text(L10n.text("NOMBRE")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("TIPO")).frame(width: 82, alignment: .leading)
                Text(L10n.text("MODIFICADO")).frame(width: 118, alignment: .leading)
                Text(L10n.text("ESPACIO EN DISCO")).frame(width: 162, alignment: .trailing)
            }
            .font(SoraTypography.body(10, weight: .semibold)).foregroundStyle(SoraPalette.secondary)
            .padding(.horizontal, 28).padding(.vertical, 12)
            SoraDivider()
            if let error = explorer.error {
                emptyState(icon: "shield-alert", title: L10n.text("No se puede leer la carpeta"), detail: error)
                HStack {
                    Spacer()
                    Button(L10n.text("Acceso total al disco")) { cleaner.openFullDiskAccessSettings() }
                    Button(L10n.text("Elegir otra carpeta")) { explorer.chooseFolder() }
                    Spacer()
                }.padding(.bottom, 28)
            } else if explorer.visibleEntries.isEmpty {
                if explorer.isScanning {
                    SoraLoadingState(title: L10n.text("Leyendo carpeta…"))
                } else {
                    emptyState(icon: "folder", title: explorer.entries.isEmpty ? L10n.text("Carpeta vacía") : L10n.text("Sin coincidencias"),
                               detail: explorer.entries.isEmpty ? L10n.text("No hay elementos en esta carpeta.") : L10n.text("Prueba otro nombre o cambia los filtros."))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { entry in
                            row(entry, largestSize: largestSize)
                            SoraDivider().padding(.leading, 78)
                        }
                    }
                }
            }
            SoraDivider()
            footer
        }
        .background(SoraPalette.main)
        .soraAnimate(editingPath)
        .soraAnimate(explorer.isScanning)
        .onAppear { if !explorer.hasLoaded { explorer.scan() } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("Explora tu espacio")).font(SoraTypography.body(28, weight: .bold))
                Text(L10n.text("Cada carpeta, con su tamaño total a simple vista."))
                    .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(summary).font(SoraTypography.body(26, weight: .semibold)).monospacedDigit()
                Text(explorer.isScanning ? L10n.text("Calculando el contenido") : L10n.text("Contenido de la carpeta"))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            }
        }.padding(28)
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button(action: explorer.back) { LucideIcon("chevron-left") }.buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                .disabled(explorer.backHistory.isEmpty).help(L10n.text("Volver")).accessibilityLabel(L10n.text("Volver"))
            Button(action: explorer.forward) { LucideIcon("chevron-right") }.buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                .disabled(explorer.forwardHistory.isEmpty).help(L10n.text("Avanzar")).accessibilityLabel(L10n.text("Avanzar"))
            Button { explorer.open(explorer.folder.deletingLastPathComponent()) } label: { LucideIcon("arrow-up") }
                .buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                .disabled(explorer.folder.path == "/").help(L10n.text("Carpeta superior")).accessibilityLabel(L10n.text("Carpeta superior"))
            if editingPath {
                TextField(L10n.text("Ruta de la carpeta"), text: $pathText)
                    .textFieldStyle(SoraTextFieldStyle())
                    .onSubmit {
                        explorer.open(URL(fileURLWithPath: NSString(string: pathText).expandingTildeInPath))
                        editingPath = false
                    }
                Button(L10n.text("Cancelar")) { editingPath = false }.buttonStyle(SoraButtonStyle(kind: .ghost))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(explorer.breadcrumbs, id: \.path) { url in
                                Button(url.path == "/" ? "Mac" : url.lastPathComponent) { explorer.open(url) }
                                    .buttonStyle(.plain).foregroundStyle(url == explorer.folder ? Color.primary : .secondary)
                                    .id(url.path)
                                if url != explorer.folder { LucideIcon("chevron-right").font(SoraTypography.body(8)).foregroundStyle(SoraPalette.muted) }
                            }
                        }.font(SoraTypography.body(13)).padding(.horizontal, 8)
                    }
                    .onAppear { proxy.scrollTo(explorer.folder.path, anchor: .trailing) }
                    .onChange(of: explorer.folder) { url in proxy.scrollTo(url.path, anchor: .trailing) }
                }
                Button {
                    pathText = explorer.folder.path; editingPath = true
                } label: { LucideIcon("pencil") }.buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                    .help(L10n.text("Ir a una ruta")).accessibilityLabel(L10n.text("Ir a una ruta"))
            }
            Button(action: explorer.chooseFolder) { SoraLabel(L10n.text("Elegir carpeta"), icon: "folder-plus") }
                .buttonStyle(SoraButtonStyle(kind: .primary))
            Button(action: explorer.scan) { LucideIcon("refresh-cw") }.buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                .help(L10n.text("Volver a analizar")).accessibilityLabel(L10n.text("Volver a analizar"))
        }.padding(.horizontal, 28).padding(.bottom, 18)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            SoraSearchField(title: L10n.text("Buscar en esta carpeta"), text: $explorer.search)
                .frame(minWidth: 140, maxWidth: 280)
            SoraSelect(title: L10n.text("Mostrar"), selection: $explorer.filter, options: FileKindFilter.allCases,
                       text: { $0.rawValue }).frame(width: 110)
            Spacer(minLength: 0)
            Toggle(L10n.text("Ocultos"), isOn: $explorer.showHidden).toggleStyle(SoraCheckboxStyle()).font(SoraTypography.body(12))
            SoraSelect(title: L10n.text("Orden"), selection: $explorer.order, options: FileOrder.allCases,
                       text: { $0.rawValue }).frame(width: 210)
        }.padding(.horizontal, 28).padding(.bottom, 18)
    }

    private func safetyColor(_ safety: DeletionSafety) -> Color {
        switch safety {
        case .regenerable: return SoraPalette.color(light: 0x16813f, dark: 0x59d48a)
        case .sensitive: return SoraPalette.color(light: 0xcb3636, dark: 0xff7676)
        case .review: return SoraPalette.muted
        }
    }

    private var deletionFilters: some View {
        HStack(spacing: 8) {
            Text(L10n.text("BORRADO")).font(SoraTypography.body(10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(SoraPalette.muted).padding(.trailing, 4)
            Button { explorer.safetyFilter = nil } label: {
                Text(L10n.text("Todos")).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(explorer.safetyFilter == nil ? SoraPalette.elevated : .clear, in: Capsule())
            }.buttonStyle(.plain).accessibilityAddTraits(explorer.safetyFilter == nil ? .isSelected : [])
            ForEach(DeletionSafety.allCases) { safety in
                Button { explorer.safetyFilter = safety } label: {
                    HStack(spacing: 6) {
                        Circle().fill(safetyColor(safety)).frame(width: 7, height: 7)
                        Text(L10n.string(safety.rawValue))
                    }.padding(.horizontal, 10).padding(.vertical, 6)
                        .background(explorer.safetyFilter == safety ? SoraPalette.elevated : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(explorer.safetyFilter == safety ? .isSelected : [])
            }
            Spacer(minLength: 0)
            LucideIcon("info").foregroundStyle(SoraPalette.muted)
                .help(L10n.text("Verde: cachés conocidas y regenerables. Rojo: sistema, configuración o datos sensibles. Gris: revisar. La clasificación depende de la ubicación; pasa el cursor sobre cada punto para ver el motivo."))
        }.font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
            .padding(.horizontal, 28).padding(.bottom, 14)
    }

    private func row(_ entry: FileEntry, largestSize: Int64) -> some View {
        HStack(spacing: 12) {
            LucideIcon(entry.isSymbolicLink ? "link" : entry.isDirectory ? "folder" : "file", size: 22)
                .font(SoraTypography.body(21))
                .foregroundStyle(entry.isDirectory ? SoraPalette.accent : SoraPalette.accentHover)
                .frame(width: 32, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle().fill(safetyColor(entry.deletion.safety)).frame(width: 8, height: 8)
                        .help(L10n.string(entry.deletion.safety.rawValue) + ": " + entry.deletion.explanation)
                        .accessibilityLabel(L10n.string(entry.deletion.safety.rawValue) + ": " + entry.deletion.explanation)
                    Text(entry.name).font(SoraTypography.body(13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                if entry.measurement?.isPartial == true {
                    Text(L10n.text("Tamaño parcial · acceso limitado")).font(SoraTypography.body(10)).foregroundStyle(.orange)
                } else if entry.isSymbolicLink {
                    Text(L10n.text("Destino sin recorrer")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.kind).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).frame(width: 82, alignment: .leading)
            Text(entry.modified.map { L10n.date($0) } ?? "—")
                .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).frame(width: 118, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let measurement = entry.measurement {
                    Text((measurement.isPartial ? "≥ " : "") + formatDiskBytes(measurement.bytes))
                        .font(SoraTypography.body(13, weight: .semibold)).monospacedDigit()
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SoraPalette.elevated)
                            Capsule().fill(entry.isDirectory ? SoraPalette.accent.opacity(0.65) : SoraPalette.accentHover)
                                .frame(width: max(0, geometry.size.width * (largestSize > 0 ? Double(measurement.bytes) / Double(largestSize) : 0)))
                        }
                    }.frame(width: 104, height: 4).soraAnimate(measurement.bytes)
                } else {
                    Text(explorer.isScanning ? L10n.text("Calculando…") : L10n.text("Pendiente")).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
                }
            }.frame(width: 162, alignment: .trailing)
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if entry.isDirectory { explorer.open(entry.url) } else { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } }
        .contextMenu {
            if entry.isDirectory { Button(L10n.text("Abrir carpeta")) { explorer.open(entry.url) } }
            Button(L10n.text("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button(L10n.text("Copiar ruta")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url.path, forType: .string) }
        }
        .help(entry.url.path + "\n" + L10n.string(entry.deletion.safety.rawValue) + ": " + entry.deletion.explanation + (entry.isDirectory ? L10n.text("\nDoble clic para abrir") : ""))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(entry.isDirectory ? L10n.text("Abrir carpeta") : L10n.text("Mostrar en Finder"))) {
            if entry.isDirectory { explorer.open(entry.url) } else { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if explorer.isScanning { SoraSpinner().controlSize(.mini) }
            Text(explorer.status).font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).lineLimit(1)
            if explorer.isScanning { Button(L10n.text("Detener"), action: explorer.stop).font(SoraTypography.body(12)) }
            Spacer()
            Text(L10n.text("\(explorer.visibleEntries.count) visibles / \(explorer.entries.count) · tamaños asignados en disco"))
                .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary)
            DiskAccessButton(access: diskAccess) { cleaner.openFullDiskAccessSettings() }
        }.padding(.horizontal, 28).padding(.vertical, 14)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            LucideIcon(icon, size: 36).foregroundStyle(SoraPalette.accent)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}
