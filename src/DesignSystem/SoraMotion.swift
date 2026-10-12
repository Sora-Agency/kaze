import SwiftUI

enum SoraMotion {
    static let interaction = Animation.easeOut(duration: 0.16)
    static let content = Animation.easeInOut(duration: 0.24)
    static let entrance = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let collapse = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)
}

struct SoraEntrance: ViewModifier {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? nil : SoraMotion.entrance.delay(delay)) { appeared = true }
            }
    }
}

struct SoraSpinner: View {
    var size: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            ZStack {
                Circle().stroke(SoraPalette.accent.opacity(0.15), lineWidth: 2)
                Circle().trim(from: 0.08, to: 0.76)
                    .stroke(SoraPalette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : phase * 360))
            }.frame(width: size, height: size)
        }.accessibilityLabel(L10n.text("Cargando"))
    }
}

struct SoraLoadingState: View {
    var title: String
    var body: some View {
        VStack(spacing: 16) {
            SoraSpinner(size: 30)
            Text(title).font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(SoraEntrance())
    }
}

extension View {
    func soraEntrance(delay: Double = 0) -> some View { modifier(SoraEntrance(delay: delay)) }
    func soraAnimate<Value: Equatable>(_ value: Value) -> some View { modifier(SoraValueAnimation(value: value)) }
}

private struct SoraValueAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View { content.animation(reduceMotion ? nil : SoraMotion.content, value: value) }
}
