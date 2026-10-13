import Foundation

final class OperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func check() throws { if isCancelled { throw CancellationError() } }
}
