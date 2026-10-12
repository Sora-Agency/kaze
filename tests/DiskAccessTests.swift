import Foundation
import Darwin

@main
struct DiskAccessTests {
    @MainActor
    static func main() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            print("PASS: " + message)
        }
        check(DiskAccessProbe.check(home: home, openFile: { _ in nil }) == .available,
              "A successful protected-file open enables the check icon")
        check(DiskAccessProbe.check(home: home, openFile: { _ in ENOENT }) == .unknown,
              "Missing protected files cannot be mistaken for a denied permission")
        check(DiskAccessProbe.check(home: home, openFile: { _ in EACCES }) == .unknown,
              "Ordinary UNIX access errors do not claim the privacy permission is disabled")
        check(DiskAccessProbe.check(home: home, openFile: { _ in EPERM }) == .restricted,
              "An explicit privacy restriction keeps the alert icon")
        var attempts = 0
        let fallback = DiskAccessProbe.check(home: home, openFile: { path in
            attempts += 1
            return path.hasPrefix(home.path) ? EPERM : nil
        })
        check(fallback == .available && attempts == 2,
              "A successful fallback supersedes an inconclusive first path")
        var live = DiskAccessStatus.restricted
        let store = DiskAccessStore(probe: { live })
        store.refresh()
        check(store.status == .restricted, "Initial status reflects the access check")
        live = .available
        store.refresh()
        check(store.status == .available, "Returning from Settings updates a newly granted permission")
        live = .restricted
        store.refresh()
        check(store.status == .restricted, "Revoked access removes the green check")
        live = .unknown
        store.refresh()
        check(store.status == .unknown, "An inconclusive check cannot retain a stale green status")
        check(DiskAccessStatus.available.icon == "shield-check" && DiskAccessStatus.restricted.icon == "shield-alert",
              "Permission states use their distinct shield icons")
    }
}
