import AppKit
import SwiftUI

/// Observe the native scroll viewport without publishing a state update per pixel.
struct SmartScanScrollObserver: NSViewRepresentable {
    @Binding var compact: Bool
    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = { compact = $0 }
        return probe
    }
    func updateNSView(_ probe: Probe, context: Context) {
        probe.onChange = { compact = $0 }
        probe.attach()
    }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.detach() }

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private weak var clip: NSClipView?
        private var token: NSObjectProtocol?
        private var inputToken: Any?
        private var expansionIntentUntil: TimeInterval = 0
        private var lastCompact = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleAttachment() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleAttachment() }
        private func scheduleAttachment() { DispatchQueue.main.async { [weak self] in self?.attach() } }
        func attach() {
            guard window != nil, let viewport = enclosingScrollView?.contentView else { return }
            if clip !== viewport {
                detach(); clip = viewport
                viewport.postsBoundsChangedNotifications = true
                token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: viewport, queue: .main) { [weak self] _ in self?.publishThreshold() }
                inputToken = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
                    guard let self, event.window === self.window, let clip = self.clip else { return event }
                    let towardsTop: Bool
                    if event.type == .scrollWheel {
                        guard clip.bounds.contains(clip.convert(event.locationInWindow, from: nil)) else { return event }
                        towardsTop = event.scrollingDeltaY > 0
                    } else {
                        guard [UInt16(115), 116, 121, 125, 126].contains(event.keyCode) else { return event }
                        towardsTop = [UInt16(115), 116, 126].contains(event.keyCode)
                    }
                    self.expansionIntentUntil = towardsTop ? ProcessInfo.processInfo.systemUptime + 0.3 : 0
                    DispatchQueue.main.async { [weak self] in self?.publishThreshold() }
                    return event
                }
            }
            publishThreshold()
        }
        private func publishThreshold() {
            guard let clip, let document = clip.documentView else { return }
            let offset = document.isFlipped ? clip.bounds.minY - document.bounds.minY : document.bounds.maxY - clip.bounds.maxY
            // A small hysteresis keeps elastic scrolling and layout changes from flickering.
            // Expanding the viewport can clamp a short list to its top. Only an
            // upward input should expand it again, avoiding an animated feedback loop.
            let towardsTop = ProcessInfo.processInfo.systemUptime < expansionIntentUntil
            let next = lastCompact ? !(offset <= 20 && towardsTop) : offset > 72
            guard next != lastCompact else { return }
            lastCompact = next
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.lastCompact == next else { return }
                self.onChange?(next)
            }
        }
        func detach() {
            if let token { NotificationCenter.default.removeObserver(token) }
            if let inputToken { NSEvent.removeMonitor(inputToken) }
            token = nil; inputToken = nil; clip = nil; expansionIntentUntil = 0
        }
        deinit { detach() }
    }
}
