import Foundation
import CoreServices

// Last-used metadata is optional; do not turn directory access times into usage claims.
enum SpotlightUsage {
    static func dates(for files: [(Int, URL)], cancellation: ScanCancellation, progress: (Int) -> Void) -> (dates: [Int: Date], queried: Set<Int>) {
        var dates: [Int: Date] = [:], queried = Set<Int>()
        let deadline = Date().addingTimeInterval(30)
        for (node, url) in files.prefix(500) {
            guard !cancellation.isCancelled, Date() < deadline else { break }
            #if !KAZE_PREVIEW
            if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
               let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { dates[node] = date }
            #endif
            queried.insert(node); if queried.count % 20 == 0 { progress(queried.count) }
        }
        return (dates, queried)
    }
}
