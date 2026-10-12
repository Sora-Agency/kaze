import SwiftUI
import AppKit

struct MonitorMenu: View {
    @ObservedObject var monitor: StorageMonitor
    @ObservedObject private var language = AppLanguageStore.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(L10n.text("Espacio disponible: \(formatDiskBytes(monitor.free))"))
        if let growth = monitor.growth { Text(L10n.text("Crecimiento reciente (hasta 1 h): \(formatDiskBytes(growth))")) }
        if monitor.low { Label(L10n.text("Poco espacio disponible"), systemImage: "exclamationmark.triangle") }
        if let error = monitor.error { Text(error) }
        Divider()
        ForEach([AppSection.smart, .spaceMap, .explorer, .history]) { section in
            Button(L10n.string(section.rawValue)) {
                if let window = NSApplication.shared.windows.first(where: { $0.title == "Kaze · Sora" && $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                } else { openWindow(id: "main") }
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .showKazeSection, object: section)
                }
            }
        }
        Divider()
        Button(L10n.text("Actualizar medición")) { monitor.refresh() }
        Button(L10n.text("Salir de Kaze")) { NSApplication.shared.terminate(nil) }
    }
}
