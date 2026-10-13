import Foundation
import CryptoKit
import Darwin

final class LocalAIService: @unchecked Sendable {
    let package: LocalAIPackage
    let directory: URL
    private let storage: LocalAIStorage
    var hasInstallation: Bool { storage.exists }

    func uninstall() throws {
        stopExecution()
        try storage.uninstall()
        validated = [:]
    }
    private var validated: [String: FileFingerprint] = [:]
    typealias Downloader = (LocalAIAsset, URL, ScanCancellation, @escaping (Int64) -> Void) throws -> Void
    private let downloader: Downloader
    private let processLock = NSLock()
    private var activeProcess: Process?

    func stopExecution() {
        processLock.lock(); let process = activeProcess; processLock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, package: LocalAIPackage = .bundled,
         downloader: @escaping Downloader = LocalAIService.download) {
        self.package = package
        storage = LocalAIStorage(home: home)
        directory = storage.root.appendingPathComponent(package.version)
        self.downloader = downloader
    }

    func validate(cancellation: ScanCancellation) throws -> Bool {
        let assets = [package.engine, package.model]
        guard assets.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.filename).path) }) else { validated = [:]; return false }
        for asset in assets {
            let url = directory.appendingPathComponent(asset.filename)
            guard let s = DiskScanner.metadata(url), (s.st_mode & S_IFMT) == S_IFREG, s.st_size == asset.bytes,
                  canonicalFilePath(url) == url.path else { throw LocalAIError.integrity }
            let fingerprint = StorageIndexer.fingerprint(s)
            if validated[asset.filename] != fingerprint {
                guard try Self.sha256(url, cancellation: cancellation) == asset.sha256 else { throw LocalAIError.integrity }
                guard let after = DiskScanner.metadata(url), StorageIndexer.fingerprint(after) == fingerprint else { throw LocalAIError.integrity }
                validated[asset.filename] = fingerprint
            }
        }
        return true
    }

    func install(cancellation: ScanCancellation, progress: @escaping (Double) -> Void) throws {
        guard LocalAIPackage.supported else { throw LocalAIError.unsupported }
        let fm = FileManager.default
        let space = try fm.attributesOfFileSystem(forPath: fm.homeDirectoryForCurrentUser.path)
        guard ((space[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) >= 1_500_000_000 else { throw LocalAIError.space }
        let parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent(".install-\(UUID())")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        var completed: Int64 = 0
        for asset in [package.engine, package.model] {
            let offset = completed
            let destination = stage.appendingPathComponent(asset.filename)
            try downloader(asset, destination, cancellation) { bytes in
                progress(min(0.95, Double(offset + bytes) / Double(self.package.downloadBytes) * 0.95))
            }
            guard !cancellation.isCancelled else { throw LocalAIError.cancelled }
            guard let metadata = DiskScanner.metadata(destination), (metadata.st_mode & S_IFMT) == S_IFREG,
                  metadata.st_size == asset.bytes else { throw LocalAIError.integrity }
            guard try Self.sha256(destination, cancellation: cancellation) == asset.sha256 else { throw LocalAIError.integrity }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            completed += asset.bytes
        }
        guard !cancellation.isCancelled else { throw LocalAIError.cancelled }
        let license = Bundle.main.resourceURL?.appendingPathComponent("AI/Qwen-LICENSE.txt")
        if let license, fm.fileExists(atPath: license.path) { try fm.copyItem(at: license, to: stage.appendingPathComponent("Qwen-LICENSE.txt")) }
        let backup = parent.appendingPathComponent(".previous-\(UUID())")
        let exists = fm.fileExists(atPath: directory.path)
        if exists { try fm.moveItem(at: directory, to: backup) }
        do { try fm.moveItem(at: stage, to: directory) }
        catch { if exists { try? fm.moveItem(at: backup, to: directory) }; throw error }
        if exists { try? fm.removeItem(at: backup) }
        validated = [:]
        guard try validate(cancellation: cancellation) else { throw LocalAIError.integrity }
        progress(1)
    }

    static func sha256(_ url: URL, cancellation: ScanCancellation) throws -> String {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw LocalAIError.integrity }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            guard !cancellation.isCancelled else { throw LocalAIError.cancelled }
            let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }; digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func answer(prompt: String, cancellation: ScanCancellation, timeout: TimeInterval = 90) throws -> String {
        guard try validate(cancellation: cancellation) else { throw LocalAIError.notInstalled }
        guard LocalAIPackage.supported else { throw LocalAIError.unsupported }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("kaze-inference-\(UUID())")
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let extraction = CleanerOperations.runCommand("/usr/bin/tar", arguments: ["-xzf", directory.appendingPathComponent(package.engine.filename).path, "-C", work.path], timeout: 15)
        guard extraction.status == 0 else { throw LocalAIError.engine }
        guard !cancellation.isCancelled else { throw LocalAIError.cancelled }
        let engine = work.appendingPathComponent(package.engineFolder)
        let input = work.appendingPathComponent("prompt.txt")
        try prompt.write(to: input, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        let output = work.appendingPathComponent("response.txt")
        _ = fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
        let process = Process()
        process.executableURL = engine.appendingPathComponent("llama-completion")
        process.arguments = ["-m", directory.appendingPathComponent(package.model.filename).path, "-f", input.path,
            "--no-conversation", "--no-display-prompt", "--simple-io", "--no-warmup", "--log-verbosity", "0",
            "--offline", "--color", "off", "-n", "384", "-c", "4096", "-t", "2", "-tb", "2", "-ngl", "0", "--temp", "0.2", "--seed", "42"]
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "en_US.UTF-8", "GGML_BACKEND_PATH": engine.path,
            "GGML_METAL_PATH_RESOURCES": engine.path, "OMP_NUM_THREADS": "2"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = writer; process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        processLock.lock(); activeProcess = process; processLock.unlock()
        defer { processLock.lock(); activeProcess = nil; processLock.unlock() }
        if cancellation.isCancelled { process.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        var stopped: LocalAIError?
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation.isCancelled || Date() >= deadline {
                stopped = cancellation.isCancelled ? .cancelled : .timeout
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 2)
                }
                break
            }
        }
        if let stopped { throw stopped }
        guard !cancellation.isCancelled else { throw LocalAIError.cancelled }
        guard process.terminationStatus == 0 else { throw LocalAIError.engine }
        let reader = try FileHandle(forReadingFrom: output); defer { try? reader.close() }
        let bytes = try reader.read(upToCount: 65_536) ?? Data()
        var response = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if response.hasSuffix("[end of text]") {
            response = String(response.dropLast("[end of text]".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !response.isEmpty else { throw LocalAIError.engine }
        return response
    }

    static func download(asset: LocalAIAsset, destination: URL, cancellation: ScanCancellation, progress: @escaping (Int64) -> Void) throws {
        let transfer = AIDownload(asset: asset, destination: destination, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: asset.url); task.resume()
        while transfer.finished.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation.isCancelled { task.cancel(); throw LocalAIError.cancelled }
        }
        if let error = transfer.error { throw error }
        guard transfer.saved else { throw LocalAIError.download }
    }
}

private final class AIDownload: NSObject, URLSessionDownloadDelegate {
    let asset: LocalAIAsset, destination: URL
    let progress: (Int64) -> Void
    let finished = DispatchSemaphore(value: 0)
    var error: Error?
    var saved = false
    init(asset: LocalAIAsset, destination: URL, progress: @escaping (Int64) -> Void) {
        self.asset = asset; self.destination = destination; self.progress = progress
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > asset.bytes { error = LocalAIError.integrity; downloadTask.cancel() }
        else { progress(totalBytesWritten) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
              let size = try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber, size.int64Value == asset.bytes else { error = LocalAIError.download; return }
        do { try FileManager.default.moveItem(at: location, to: destination); saved = true }
        catch { self.error = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if self.error == nil { self.error = error }; finished.signal()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
