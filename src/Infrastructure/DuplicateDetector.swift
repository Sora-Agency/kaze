import Foundation
import CryptoKit
import Vision
import ImageIO
import Darwin

enum DuplicateDetector {
    static func imageData(_ file: IndexedFile, cancellation: ScanCancellation) -> Data? {
        guard file.fingerprint.size <= 33_554_432, canonicalFilePath(file.url) == file.url.path else { return nil }
        let fd = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var s = stat()
        guard fstat(fd, &s) == 0, (s.st_mode & S_IFMT) == S_IFREG,
              (s.st_flags & UInt32(SF_DATALESS)) == 0, StorageIndexer.fingerprint(s) == file.fingerprint else { return nil }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 65_536)
        while !cancellation.isCancelled {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 {
                guard fstat(fd, &s) == 0, StorageIndexer.fingerprint(s) == file.fingerprint else { return nil }
                return data
            }
            guard data.count + count <= 33_554_432 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return nil
    }
    static func eligible(_ file: IndexedFile, index: StorageIndex) -> Bool {
        AnalysisProtection.duplicateEligible(file.url, home: index.home)
    }
    static func hash(_ file: IndexedFile, cancellation: ScanCancellation, deadline: Date? = nil) -> String? {
        guard !file.protected, !file.directory, !file.symbolicLink, file.links == 1,
              canonicalFilePath(file.url) == file.url.path else { return nil }
        let descriptor = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              (before.st_flags & UInt32(SF_DATALESS)) == 0,
              StorageIndexer.fingerprint(before) == file.fingerprint else { return nil }
        let forkLength = fgetxattr(descriptor, "com.apple.ResourceFork", nil, 0, 0, 0)
        guard forkLength <= 0, forkLength == 0 || errno == ENOATTR || errno == ENOTSUP else { return nil }
        // Resource forks may hold unique content even when data forks match.
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while !cancellation.isCancelled {
            if let deadline, Date() >= deadline { return nil }
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 {
                var after = stat()
                guard fstat(descriptor, &after) == 0, StorageIndexer.fingerprint(after) == file.fingerprint else { return nil }
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return nil
    }

    static func exact(index: StorageIndex, cancellation: ScanCancellation, byteBudget: Int64 = 8_589_934_592, exhaustive: Bool = false,
                      progress: (Int) -> Void = { _ in }) -> DuplicateReport {
        var report = DuplicateReport()
        report.partial = index.candidateOmitted > 0; report.skipped = index.candidateOmitted
        var sizes: [Int64: [Int]] = [:]
        for (i, file) in index.files.enumerated() where !file.directory && !file.symbolicLink && file.fingerprint.size > 0 {
            if file.protected || file.links > 1 || !eligible(file, index: index) { report.skipped += 1; continue }
            sizes[file.fingerprint.size, default: []].append(i)
        }
        var readBytes: Int64 = 0
        let deadline: Date? = exhaustive ? nil : Date().addingTimeInterval(60)
        for size in sizes.keys.sorted() where (sizes[size]?.count ?? 0) > 1 {
            if cancellation.isCancelled { report.partial = true; break }
            var hashes: [String: [Int]] = [:]
            for node in sizes[size]! {
                if cancellation.isCancelled { report.partial = true; break }
                if !exhaustive && (size > byteBudget - readBytes || report.examined >= 10_000 || Date() >= deadline!) {
                    report.skipped += 1; report.partial = true; continue
                }
                if !exhaustive { readBytes += size }
                if let digest = hash(index.files[node], cancellation: cancellation, deadline: deadline) { hashes[digest, default: []].append(node); report.examined += 1 }
                else { report.skipped += 1; report.partial = true }
                if report.examined % 32 == 0 { progress(report.examined) }
            }
            for (digest, nodes) in hashes where nodes.count > 1 {
                let ordered = nodes.sorted { index.files[$0].url.path < index.files[$1].url.path }
                report.exact.append(DuplicateGroup(id: digest, nodes: ordered, similar: false,
                    potential: ordered.dropFirst().reduce(0) { $0 + index.files[$1].allocated }))
            }
        }
        report.exact.sort { $0.potential > $1.potential }
        return report
    }

    // Feature prints are candidates for human review, never proof of identical content.
    static func similar(index: StorageIndex, cancellation: ScanCancellation, limit: Int = 400,
                        threshold: Float = 6, progress: (Int) -> Void = { _ in }) -> DuplicateReport {
        var report = DuplicateReport()
        var prints: [(Int, VNFeaturePrintObservation)] = []
        var groups: [Int: [Int]] = [:]
        let extensions: Set<String> = ["jpg", "jpeg", "heic", "png", "tiff", "tif"]
        for (node, file) in index.files.enumerated() where !file.directory && extensions.contains(file.url.pathExtension.lowercased()) {
            if cancellation.isCancelled { report.partial = true; break }
            guard !file.protected, !file.symbolicLink, file.links == 1, eligible(file, index: index) else { report.skipped += 1; continue }
            guard prints.count < limit else { report.skipped += 1; report.partial = true; continue }
            let feature: VNFeaturePrintObservation? = autoreleasepool {
                guard canonicalFilePath(file.url) == file.url.path,
                      let s = DiskScanner.metadata(file.url), StorageIndexer.fingerprint(s) == file.fingerprint,
                      (s.st_flags & UInt32(SF_DATALESS)) == 0,
                      let imageData = imageData(file, cancellation: cancellation),
                      let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                let request = VNGenerateImageFeaturePrintRequest()
                request.revision = VNGenerateImageFeaturePrintRequestRevision1
                request.usesCPUOnly = true
                try? VNImageRequestHandler(cgImage: image).perform([request])
                guard let after = DiskScanner.metadata(file.url), StorageIndexer.fingerprint(after) == file.fingerprint else { return nil }
                return request.results?.first as? VNFeaturePrintObservation
            }
            guard let feature else { report.skipped += 1; report.partial = true; continue }
            var nearest: (Int, Float)?
            for (other, print) in prints {
                if cancellation.isCancelled { break }
                var distance: Float = 0
                if (try? feature.computeDistance(&distance, to: print)) != nil, distance < threshold,
                   nearest == nil || distance < nearest!.1 { nearest = (other, distance) }
            }
            if let nearest { groups[nearest.0, default: [nearest.0]].append(node) }
            prints.append((node, feature)); report.examined += 1
            if report.examined % 8 == 0 { progress(report.examined) }
        }
        report.similar = groups.sorted { $0.key < $1.key }.map {
            DuplicateGroup(id: "vision:\($0.key)", nodes: $0.value, similar: true, potential: 0)
        }
        return report
    }
}
