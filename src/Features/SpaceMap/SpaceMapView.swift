import SwiftUI
import AppKit

struct SpaceMapView: View {
    @ObservedObject var model: SmartScanModel
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewState private var focus: Int?
    @ViewState private var preview: URL?
    @ViewState private var hovered: Int?
    var openExplorer: (URL) -> Void
    private var validFocus: Int? { focus.flatMap { model.index.files.indices.contains($0) ? $0 : nil } }
    private var children: [Int] {
        (model.index.children[validFocus ?? -1] ?? []).filter { model.index.files[$0].allocated > 0 }
            .sorted { model.index.files[$0].allocated > model.index.files[$1].allocated }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnalysisHeader(title: "Kaze Space Map", subtitle: "El espacio asignado, carpeta por carpeta.", model: model)
            HStack {
                Button { if let focus = validFocus { self.focus = model.index.files[focus].parent } } label: { SoraLabel(L10n.text("Carpeta superior"), icon: "arrow-up") }.disabled(validFocus == nil)
                Button("Mac") { focus = nil }
                Text(validFocus.map { model.index.files[$0].url.path } ?? L10n.text("Raíces analizadas"))
                    .font(SoraTypography.body(12)).foregroundStyle(SoraPalette.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let focus = validFocus { Button(L10n.text("Abrir en Explorador")) { openExplorer(model.index.files[focus].url) } }
            }.padding(.horizontal, 28).padding(.bottom, 16)
            if children.isEmpty && (validFocus.map { model.index.files[$0].allocated } ?? model.index.allocated) == 0 {
                Text(L10n.text("Analiza una carpeta para dibujar su mapa de espacio."))
                    .foregroundStyle(SoraPalette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let visible = Array(children.prefix(120))
                    let fullSize = validFocus.map { model.index.files[$0].allocated } ?? model.index.allocated
                    let rest = max(0, fullSize - visible.reduce(Int64(0)) { $0 + model.index.files[$1].allocated })
                    let weights = visible.map { ($0, model.index.files[$0].allocated) } + (rest > 0 ? [(-1, rest)] : [])
                    let tiles = SpaceMapLayout.tiles(weights: weights, in: CGRect(origin: .zero, size: geometry.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(tiles) { tile in
                            if tile.id >= 0 {
                                let file = model.index.files[tile.id]
                                Button {
                                    if file.directory { focus = tile.id } else { preview = file.url }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if tile.rect.width > 65 && tile.rect.height > 32 {
                                            Text(file.url.lastPathComponent).font(SoraTypography.body(12, weight: .semibold)).lineLimit(2)
                                            if tile.rect.height > 65 { Text(formatDiskBytes(file.allocated)).font(SoraTypography.body(11)) }
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(tile.rect.width > 65 ? 12 : 0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }.buttonStyle(.plain)
                                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                                    .frame(width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3))
                                    .background(color(tile.id).opacity(hovered == tile.id ? 0.95 : 0.78), in: RoundedRectangle(cornerRadius: 7))
                                    .clipped().offset(x: tile.rect.minX, y: tile.rect.minY)
                                    .onHover { hovered = $0 ? tile.id : nil }
                                    .help(file.url.path + "\n" + formatDiskBytes(file.allocated))
                                    .accessibilityLabel(file.url.lastPathComponent + ", " + formatDiskBytes(file.allocated))
                                    .contextMenu {
                                        Button(L10n.text("Quick Look")) { preview = file.url }
                                        Button(L10n.text("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                        if file.directory { Button(L10n.text("Abrir en Explorador")) { openExplorer(file.url) } }
                                    }
                            } else {
                                Text(tile.rect.width > 65 && tile.rect.height > 32 ? L10n.text("Más elementos") : "")
                                    .font(SoraTypography.body(11)).frame(width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3))
                                    .background(SoraPalette.elevated, in: RoundedRectangle(cornerRadius: 7))
                                    .clipped().offset(x: tile.rect.minX, y: tile.rect.minY)
                                    .contextMenu { if let focus = validFocus {
                                        Button(L10n.text("Abrir en Explorador")) { openExplorer(model.index.files[focus].url) }
                                    } }
                            }
                        }
                    }
                }.padding(.horizontal, 28).padding(.bottom, 16)
                ScrollView(.horizontal) {
                    HStack { ForEach(Array(children.prefix(300)), id: \.self) { child in
                        let file = model.index.files[child]
                        Button(file.url.lastPathComponent) { if file.directory { focus = child } else { preview = file.url } }
                            .help(file.url.path).font(SoraTypography.body(11))
                    } }
                }.padding(.horizontal, 28)
            }
            AnalysisNotice(model: model)
        }.kazeQuickLook($preview)
            .onAppear { if focus == nil { focusSingleRoot() } }
            .onChange(of: model.index.date) { _ in focus = nil; hovered = nil; focusSingleRoot() }
    }
    private func focusSingleRoot() {
        let roots = model.index.children[-1] ?? []
        if roots.count == 1 { focus = roots.first }

    }
    private func color(_ node: Int) -> Color {
        let colors: [Color] = [Color(red: 0.28, green: 0.44, blue: 0.62), Color(red: 0.27, green: 0.48, blue: 0.41),
            Color(red: 0.47, green: 0.36, blue: 0.62), Color(red: 0.58, green: 0.40, blue: 0.22), Color(red: 0.27, green: 0.47, blue: 0.56)]
        return colors[node % colors.count]
    }
}
