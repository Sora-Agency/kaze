import AppKit
import Foundation

@main
struct UpdaterTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        defer {
            if let identifier = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: identifier)
            }
        }
        let updater = AppUpdater.shared
        updater.start()
        precondition(updater.canCheckForUpdates, "The embedded Sparkle updater must start successfully")
        precondition(!updater.automaticallyChecksForUpdates, "Startup must respect disabled automatic checks")
        updater.setAutomaticChecks(true)
        precondition(updater.automaticallyChecksForUpdates, "Enabling automatic checks must update the UI")
        updater.setAutomaticChecks(false)
        precondition(!updater.automaticallyChecksForUpdates, "Disabling automatic checks must update the UI")
        updater.start()
        precondition(!updater.automaticallyChecksForUpdates, "Starting a second window must not reset the preference")
        print("PASS: Sparkle starts, publishes menu state and preserves the user's automatic-check preference.")
    }
}
