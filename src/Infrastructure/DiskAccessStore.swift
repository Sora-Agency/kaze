import Foundation
import Combine
import Darwin

enum DiskAccessStatus: Equatable {
    case unknown, restricted, available

    var icon: String { self == .available ? "shield-check" : "shield-alert" }
    var description: String {
        switch self {
        case .available: return L10n.text("Acceso a carpetas protegidas verificado")
        case .restricted: return L10n.text("Acceso a carpetas protegidas pendiente")
        case .unknown: return L10n.text("Acceso a carpetas protegidas sin verificar")
        }
    }
}

enum DiskAccessProbe {
    static func check(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      openFile: (String) -> Int32? = openReadOnly) -> DiskAccessStatus {
        let paths = [home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
                     "/Library/Application Support/com.apple.TCC/TCC.db"]
        var privacyDenied = false
        for path in paths {
            guard let error = openFile(path) else { return .available }
            if error == EPERM { privacyDenied = true }
        }
        return privacyDenied ? .restricted : .unknown
    }

    private static func openReadOnly(_ path: String) -> Int32? {
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return errno }
        Darwin.close(descriptor)
        return nil
    }
}

@MainActor
final class DiskAccessStore: ObservableObject {
    @Published private(set) var status: DiskAccessStatus
    private let probe: () -> DiskAccessStatus

    init(initialStatus: DiskAccessStatus = .unknown, probe: (() -> DiskAccessStatus)? = nil) {
        status = initialStatus
        #if KAZE_PREVIEW
        self.probe = probe ?? { initialStatus }
        #else
        self.probe = probe ?? { DiskAccessProbe.check() }
        #endif
    }

    func refresh() { status = probe() }
}
