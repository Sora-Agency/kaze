import Foundation
import Darwin

final class MutationLease {
    private let url: URL
    init(url: URL = URL(fileURLWithPath: "/tmp/com.soraagency.kaze.lock")) throws {
        self.url = url
        guard mkdir(url.path, 0o700) == 0 else { throw CocoaError(.fileLocking) }
    }
    deinit { _ = rmdir(url.path) }
}
