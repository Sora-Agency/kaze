import SwiftUI

enum SoraButtonKind { case primary, secondary, ghost, destructive }

struct SoraButtonStyle: ButtonStyle {
    var kind: SoraButtonKind = .secondary
    var iconOnly = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var hovering = false

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .destructive: return SoraPalette.danger
        case .secondary, .ghost: return hovering ? SoraPalette.text : SoraPalette.secondary
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return hovering ? SoraPalette.accentHover : SoraPalette.accent
        case .secondary: return hovering ? SoraPalette.elevated : SoraPalette.surface
        case .ghost: return hovering ? SoraPalette.elevated : .clear
        case .destructive: return SoraPalette.danger.opacity(hovering ? 0.12 : 0.06)
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SoraTypography.body(12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : 14)
            .frame(width: iconOnly ? 36 : nil, height: 36)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(kind == .secondary ? SoraPalette.borderSoft : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: hovering)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: configuration.isPressed)
    }
}

struct SoraNavigationButtonStyle: ButtonStyle {
    @ViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? SoraPalette.elevated.opacity(0.6) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: hovering)
    }
}
