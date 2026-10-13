import SwiftUI
import AppKit

extension Notification.Name {
    static let showKazeLegal = Notification.Name("kaze.showLegal")
}

#if !KAZE_PREVIEW
@main
struct KazeApp: App {
    @StateObject private var language = AppLanguageStore.shared
    @StateObject private var updater = AppUpdater.shared
    @StateObject private var monitor = StorageMonitor.shared
    @AppStorage("kaze.monitor.enabled") private var monitorEnabled = true
    init() {
        OperationCLI.runIfRequested()
        AppIdentity.migratePreferences()
    }
    var body: some Scene {
        WindowGroup("Kaze · Sora", id: "main") {
            ContentView().environment(\.locale, language.locale)
                .onAppear { updater.start(); monitor.setEnabled(monitorEnabled) }
                .onChange(of: monitorEnabled) { monitor.setEnabled($0) }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("Acerca de Kaze")) { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
                Button(L10n.text("Términos, privacidad y licencia")) {
                    NotificationCenter.default.post(name: .showKazeLegal, object: nil)
                }
            }
            CommandGroup(after: .appInfo) {
                Toggle(L10n.text("Monitor ligero en la barra de menús"), isOn: $monitorEnabled)
                Button(L10n.text("Buscar actualizaciones…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Toggle(L10n.text("Buscar actualizaciones automáticamente"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticChecks($0) }
                ))
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("Términos y licencia de Kaze")) {
                    NotificationCenter.default.post(name: .showKazeLegal, object: nil)
                }
            }
        }
        MenuBarExtra(isInserted: Binding(
            get: { monitorEnabled },
            set: { if monitorEnabled != $0 { monitorEnabled = $0 } }
        )) {
            MonitorMenu(monitor: monitor)
        } label: {
            Label(monitor.measured == nil ? "Kaze" : "Kaze " + formatDiskBytes(monitor.free),
                  systemImage: monitor.low ? "externaldrive.badge.exclamationmark" : "externaldrive")
        }
    }
}
#endif
