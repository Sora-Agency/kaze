import SwiftUI
import AppKit

extension Notification.Name {
    static let showKazeLegal = Notification.Name("kaze.showLegal")
}

#if !KAZE_PREVIEW
@main
struct KazeApp: App {
    @StateObject private var language = AppLanguageStore.shared
    init() { AppIdentity.migratePreferences() }
    var body: some Scene {
        WindowGroup("Kaze · Sora") { ContentView().environment(\.locale, language.locale) }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("Acerca de Kaze")) { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
                Button(L10n.text("Términos, privacidad y licencia")) {
                    NotificationCenter.default.post(name: .showKazeLegal, object: nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("Términos y licencia de Kaze")) {
                    NotificationCenter.default.post(name: .showKazeLegal, object: nil)
                }
            }
        }
    }
}
#endif
