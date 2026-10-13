import Foundation
import CoreServices

struct FolderChanges {
    var paths: Set<String> = []
    var full = false
    var historyDone = false
    var eventID: UInt64 = 0
    mutating func merge(_ other: FolderChanges) {
        full = full || other.full; historyDone = historyDone || other.historyDone
        eventID = max(eventID, other.eventID)
        if paths.count + other.paths.count > 2048 { full = true; paths = [] }
        else { paths.formUnion(other.paths) }
    }
    func affects(_ url: URL) -> Bool {
        full || paths.contains { pathIsWithin($0, root: url.path) || pathIsWithin(url.path, root: $0) }
    }
}

final class FolderChangeMonitor {
    private let queue = DispatchQueue(label: "kaze.folder-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private let box: CallbackBox
    static func eventID() -> UInt64 { FSEventsGetCurrentEventId() }
    static func volumeID(_ device: Int64) -> String? {
        guard let uuid = FSEventsCopyUUIDForDevice(dev_t(device)) else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    init?(folder: URL, since: UInt64, ignoring: URL, handler: @escaping (FolderChanges) -> Void) {
        box = CallbackBox(folder: folder.path, ignoring: ignoring.path, handler: handler)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<CallbackBox>.fromOpaque(pointer).retain(); return pointer
            }, release: { pointer in
                if let pointer { Unmanaged<CallbackBox>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, ids in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let values = unsafeBitCast(paths, to: NSArray.self) as! [String]
            box.receive(count: count, paths: values, flags: flags, ids: ids)
        }, &context, [folder.path] as CFArray, since, 0.35,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil; return nil }
        queue.asyncAfter(deadline: .now() + 3) { [weak box] in
            guard let box, !box.historyDone else { return }
            box.historyDone = true; box.deliver(FolderChanges(full: true, historyDone: true))
        }
    }
    func stop() {
        guard let stream else { return }
        self.stream = nil
        queue.sync { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
    deinit { stop() }
    private final class CallbackBox {
        let folder: String, ignoring: String
        let handler: (FolderChanges) -> Void
        var historyDone = false
        private var pending = FolderChanges()
        init(folder: String, ignoring: String, handler: @escaping (FolderChanges) -> Void) {
            self.folder = folder; self.ignoring = ignoring; self.handler = handler
        }
        func receive(count: Int, paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, ids: UnsafePointer<FSEventStreamEventId>) {
            var changes = FolderChanges()
            for i in 0..<min(count, paths.count) {
                if flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 { changes.historyDone = true; continue }
                changes.eventID = max(changes.eventID, ids[i])
                let lost = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                    | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
                    | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount | kFSEventStreamEventFlagMount
                if flags[i] & FSEventStreamEventFlags(lost) != 0 { changes.full = true }
                let path = URL(fileURLWithPath: paths[i]).standardizedFileURL.path
                guard !pathIsWithin(path, root: ignoring), pathIsWithin(path, root: folder) else { continue }
                if changes.paths.count < 2048 { changes.paths.insert(path) } else { changes.full = true }
            }
            if !historyDone {
                pending.merge(changes)
                if changes.historyDone { historyDone = true; deliver(pending); pending = FolderChanges() }
            } else if changes.full || !changes.paths.isEmpty { deliver(changes) }
        }
        func deliver(_ changes: FolderChanges) { DispatchQueue.main.async { [handler] in handler(changes) } }
    }
}
