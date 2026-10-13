import Foundation

enum ExplorerRefreshPolicy {
    static func deferAutomaticRefresh(_ snapshot: CachedExplorerFolder) -> Bool {
        var count = 0
        for entry in snapshot.entries {
            count += min(50_000, entry.measurement?.fileCount ?? 0)
            if count >= 50_000 { return true }
        }
        return false
    }
}
