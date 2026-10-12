import Foundation
import Combine
import UserNotifications

@MainActor
final class StorageMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = StorageMonitor()
    @Published private(set) var free: Int64 = 0
    @Published private(set) var total: Int64 = 0
    @Published private(set) var growth: Int64?
    @Published private(set) var measured: Date?
    @Published private(set) var error: String?
    private var timer: Timer?
    private var samples: [(Date, Int64)] = []
    private var reading = false
    private var enabled = false
    private var wantsAlerts = false
    private var canNotify = false
    private var preferences: AnyCancellable?
    override init() {
        super.init()
        #if !KAZE_PREVIEW
        UNUserNotificationCenter.current().delegate = self
        #endif
        preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in self?.syncPreferences() }
            }
    }
    var low: Bool { measured != nil && free < 20_000_000_000 }
    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        syncAlertPreference()
        timer?.invalidate(); timer = nil
        guard enabled else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 15
    }
    private func syncPreferences() {
        setEnabled(UserDefaults.standard.object(forKey: "kaze.monitor.enabled") as? Bool ?? true)
        syncAlertPreference()
    }
    private func syncAlertPreference() {
        let wanted = UserDefaults.standard.bool(forKey: "kaze.monitor.alerts")
        guard wanted != wantsAlerts else { return }; wantsAlerts = wanted
        guard wanted else { canNotify = false; return }
        #if !KAZE_PREVIEW
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.canNotify = granted; self?.checkAlert() }
        }
        #endif
    }
    private func checkAlert() {
        guard enabled, wantsAlerts, canNotify, measured != nil else { return }
        guard low else { return }
        let last = UserDefaults.standard.double(forKey: "kaze.monitor.lastAlert")
        guard Date().timeIntervalSince1970 - last >= 21_600 else { return }
        #if !KAZE_PREVIEW
        let content = UNMutableNotificationContent()
        content.title = L10n.text("Poco espacio disponible")
        content.body = L10n.text("Quedan \(formatDiskBytes(free)). Abre Kaze Smart Scan para revisar oportunidades de limpieza.")
        content.sound = .default
        let notification = UNNotificationRequest(identifier: "kaze.lowSpace", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(notification) { error in
            if error == nil { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "kaze.monitor.lastAlert") }
        }
        #endif
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func refresh() {
        guard !reading else { return }; reading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data") }
            DispatchQueue.main.async {
                guard let self else { return }; self.reading = false
                switch result {
                case .success(let values):
                    guard let free = (values[.systemFreeSize] as? NSNumber)?.int64Value,
                          let total = (values[.systemSize] as? NSNumber)?.int64Value else {
                        self.error = L10n.text("No se pudo medir el espacio disponible."); return
                    }
                    self.free = free; self.total = total
                    let now = Date()
                    self.samples.removeAll { now.timeIntervalSince($0.0) > 3600 }
                    self.samples.append((now, free))
                    if self.samples.count > 120 { self.samples.removeFirst(self.samples.count - 120) }
                    self.growth = self.samples.count > 1 ? self.samples.first!.1 - free : nil
                    self.measured = Date(); self.error = nil; self.checkAlert()
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
