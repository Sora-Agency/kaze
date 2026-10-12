import Foundation
import AppKit

@MainActor
final class StartupItemsModel: ObservableObject {
    @Published private(set) var items: [StartupItem]
    @Published private(set) var busy = false
    @Published private(set) var loaded: Bool
    @Published private(set) var error: String?
    private let service: StartupItemsService
    private let queue = DispatchQueue(label: "com.soraagency.kaze.startup", qos: .utility)
    init(service: StartupItemsService = StartupItemsService(), initialItems: [StartupItem]? = nil) {
        self.service = service; items = initialItems ?? []; loaded = initialItems != nil
    }
    func refresh() { let service = self.service; perform { try service.load() } }
    func set(_ item: StartupItem, enabled: Bool) { let service = self.service; perform { try service.set(item, enabled: enabled) } }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = L10n.text("Añadir al inicio")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        set(StartupItem(name: url.deletingPathExtension().lastPathComponent, path: url.path, hidden: false, enabled: false), enabled: true)
    }
    private func perform(_ work: @escaping () throws -> [StartupItem]) {
        guard !busy else { return }
        busy = true; error = nil
        queue.async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                switch result { case .success(let items): self.items = items; self.loaded = true
                case .failure(let error): self.error = String(describing: error) }
                self.busy = false
            }
        }
    }
}
