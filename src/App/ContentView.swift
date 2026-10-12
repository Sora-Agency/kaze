import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case smart = "Kaze Smart Scan", spaceMap = "Kaze Space Map", duplicates = "Duplicados", systemData = "System Data", history = "Historial", rules = "Ajustes y seguridad"
    case explorer = "Explorador", cleanup = "Limpieza", applications = "Aplicaciones", resources = "Desarrollo", logs = "Actividad", scheduled = "Tareas programadas", legal = "Términos y licencia"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .smart: return "sparkles"
        case .spaceMap: return "layout-grid"
        case .duplicates: return "file"
        case .systemData: return "hard-drive"
        case .history: return "calendar-clock"
        case .rules: return "shield-check"
        case .explorer: return "folder"
        case .cleanup: return "sparkles"
        case .applications: return "layout-grid"
        case .resources: return "hard-drive"
        case .logs: return "activity"
        case .scheduled: return "calendar-clock"
        case .legal: return "file-text"
        }
    }
}

struct ContentView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @StateObject private var model: CleanerModel
    @StateObject private var explorer: FileExplorerModel
    @StateObject private var scheduler: ScheduledTaskModel
    @StateObject private var analysis: SmartScanModel
    @StateObject private var diskAccess: DiskAccessStore
    @ViewState private var section: AppSection = .smart
    @AppStorage("kaze.appearance") private var appearance: AppAppearance = .dark
    private let previewAppearance: AppAppearance?
    private let resourceDirectory: URL?
    private let homeURL: URL
    @Environment(\.colorScheme) private var colorScheme

    @MainActor
    init(model: CleanerModel? = nil, explorer: FileExplorerModel? = nil, scheduler: ScheduledTaskModel? = nil,
         previewAppearance: AppAppearance? = nil, initialSection: AppSection = .smart,
         resourceDirectory: URL? = nil, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
         languageStore: AppLanguageStore = .shared, diskAccessStore: DiskAccessStore? = nil, analysisModel: SmartScanModel? = nil) {
        language = languageStore
        self.homeURL = homeURL
        SoraFonts.register(directory: resourceDirectory?.appendingPathComponent("Fonts"))
        _model = StateObject(wrappedValue: model ?? CleanerModel())
        _explorer = StateObject(wrappedValue: explorer ?? FileExplorerModel(folder: homeURL, home: homeURL))
        _scheduler = StateObject(wrappedValue: scheduler ?? ScheduledTaskModel.shared)
        _analysis = StateObject(wrappedValue: analysisModel ?? SmartScanModel(home: homeURL, resources: resourceDirectory ?? Bundle.main.resourceURL))
        _diskAccess = StateObject(wrappedValue: diskAccessStore ?? DiskAccessStore())
        _section = ViewState(initialValue: initialSection)
        self.previewAppearance = previewAppearance
        self.resourceDirectory = resourceDirectory
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            SoraPalette.borderSoft.frame(width: 1)
            VStack(spacing: 0) {
                topbar
                SoraDivider()
                Group {
                    switch section {
                    case .smart: SmartScanView(model: analysis) { section = $0 }
                    case .spaceMap: SpaceMapView(model: analysis) { url in section = .explorer; explorer.open(url) }
                    case .duplicates: DuplicatesView(model: analysis)
                    case .systemData: SystemDataView(model: analysis) { url in section = .explorer; explorer.open(url) }
                    case .history: HistoryView(journal: analysis.journal)
                    case .rules: RulesView(model: analysis)
                    case .explorer: ExplorerView(explorer: explorer, cleaner: model, diskAccess: diskAccess)
                    case .cleanup: DashboardView(model: model)
                    case .applications: ApplicationsView(model: model)
                    case .resources: DevelopmentView(analysis: analysis, cleaner: model)
                    case .logs: LogsView(model: model)
                    case .scheduled: ScheduledTasksView(model: scheduler)
                    case .legal: LegalView(resourceDirectory: resourceDirectory)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(section)
                    .transition(.opacity)
                    .soraEntrance()
            }
        }
        .environment(\.locale, language.locale)
        .font(SoraTypography.body(13))
        .foregroundStyle(SoraPalette.text)
        .tint(SoraPalette.accent)
        .background(SoraPalette.main)
        .buttonStyle(SoraButtonStyle())
        .textFieldStyle(SoraTextFieldStyle())
        .toggleStyle(SoraCheckboxStyle())
        .soraAnimate(section)
        .soraAnimate(appearance)
        .soraEntrance()
        .preferredColorScheme((previewAppearance ?? appearance).scheme)
        .frame(minWidth: 1130, idealWidth: 1280, minHeight: 720, idealHeight: 820)
        .navigationTitle("Kaze · Sora")
        .onReceive(NotificationCenter.default.publisher(for: .showKazeLegal)) { _ in section = .legal }
        .onAppear {
            diskAccess.refresh()
            model.sharedIndex = analysis.index; explorer.sharedIndex = analysis.index
            analysis.onIndex = { model.sharedIndex = $0; explorer.sharedIndex = $0; model.refreshStorage() }
        }
        .onReceive(OperationEvents.updates.receive(on: RunLoop.main)) { _ in
            model.sharedIndex = nil; explorer.sharedIndex = nil; analysis.markChanged(); explorer.invalidate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKazeSection)) { notification in if let target = notification.object as? AppSection { section = target } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            diskAccess.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SoraMark(size: 38, resourceDirectory: resourceDirectory)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kaze").font(SoraTypography.brand(24)).tracking(0.4)
                    Text("by Sora").font(SoraTypography.brand(11, weight: .ultraLight))
                        .foregroundStyle(SoraPalette.secondary)
                }
            }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel(L10n.text("ANALIZAR"))
                    ForEach([AppSection.smart, .spaceMap, .explorer, .duplicates, .systemData]) { navButton($0) }
                    sectionLabel(L10n.text("LIMPIAR")).padding(.top, 12)
                    ForEach([AppSection.cleanup, .applications, .resources]) { navButton($0) }
                    sectionLabel(L10n.text("GESTIONAR")).padding(.top, 12)
                    ForEach([AppSection.history, .scheduled, .rules, .logs, .legal]) { navButton($0) }
                }.padding(.horizontal, 16)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LucideIcon("hard-drive").foregroundStyle(SoraPalette.accent)
                    Text(L10n.text("Almacenamiento")).font(SoraTypography.body(12, weight: .medium))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SoraPalette.border)
                        Capsule().fill(SoraPalette.accent).frame(width: geometry.size.width * model.storage.fractionUsed)
                    }
                }.frame(height: 4).soraAnimate(model.storage.fractionUsed)
                Text(L10n.text("\(ByteCountFormatter.string(fromByteCount: model.storage.free, countStyle: .file)) disponibles"))
                    .font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary)
            }.padding(16).background(SoraPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SoraPalette.borderSoft))
                .padding(.horizontal, 20).padding(.bottom, 16)
            SoraDivider().padding(.horizontal, 20)
            UpdateButton().padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }.frame(width: 248).background(SoraPalette.sidebar)
    }

    private var topbar: some View {
        HStack(spacing: 12) {
            Text("Kaze").font(SoraTypography.body(12, weight: .medium)).foregroundStyle(SoraPalette.muted)
            Text("/").foregroundStyle(SoraPalette.border)
            Text(L10n.string(section.rawValue)).font(SoraTypography.body(12, weight: .medium))
            Spacer()
            SoraSelect(title: L10n.text("Idioma"), selection: Binding(get: { language.selection }, set: { language.select($0) }),
                       options: AppLanguage.allCases, text: { $0.name })
                .frame(width: 132).help(L10n.text("Cambiar idioma"))
            Button {
                appearance = (appearance.scheme ?? colorScheme) == .dark ? .light : .dark
            } label: {
                LucideIcon((previewAppearance ?? appearance).scheme == .light ? "moon" : "sun", size: 17)
            }.buttonStyle(SoraButtonStyle(kind: .ghost, iconOnly: true))
                .help((previewAppearance ?? appearance).scheme == .light ? L10n.text("Cambiar a modo oscuro") : L10n.text("Cambiar a modo claro"))
                .accessibilityLabel(L10n.text("Cambiar apariencia"))
                .accessibilityValue((previewAppearance ?? appearance).title)

        }.padding(.horizontal, 28).frame(height: 58).background(SoraPalette.main)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(SoraTypography.body(10, weight: .bold)).tracking(1.2)
            .foregroundStyle(SoraPalette.muted).padding(.horizontal, 10).padding(.bottom, 5)
    }

    private func navButton(_ item: AppSection) -> some View {
        Button { section = item } label: {
            HStack(spacing: 10) {
                LucideIcon(item.icon).frame(width: 18)
                    .foregroundStyle(section == item ? SoraPalette.accent : SoraPalette.muted)
                Text(L10n.string(item.rawValue)).font(SoraTypography.body(13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(section == item ? SoraPalette.text : SoraPalette.secondary)
            .padding(.horizontal, 12).frame(height: 34)
            .background(section == item ? SoraPalette.elevated : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) {
                if section == item { SoraPalette.accent.frame(width: 2, height: 20).clipShape(Capsule()) }
            }.contentShape(Rectangle())
        }.buttonStyle(SoraNavigationButtonStyle())
    }

}
