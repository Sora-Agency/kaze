#if !KAZE_PREVIEW
import AppKit
import Combine
import Sparkle

/// One updater per application, shared by every window and the app menu.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true

    private let controller: SPUStandardUpdaterController
    private var observations: Set<AnyCancellable> = []
    private var started = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
    }

    func start() {
        guard !started else { return }
        do {
            try controller.updater.start()
            started = true
            // Respect the user's setting and check on launch, before Sparkle's next runloop cycle.
            if controller.updater.automaticallyChecksForUpdates {
                controller.updater.checkForUpdatesInBackground()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.text("No se pudo iniciar el actualizador")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
#endif
