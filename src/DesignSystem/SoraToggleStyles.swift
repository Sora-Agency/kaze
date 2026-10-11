import SwiftUI

struct SoraCheckboxStyle: ToggleStyle {
    var showsLabel = true
    func makeBody(configuration: Configuration) -> some View {
        SoraCheckbox(configuration: configuration, showsLabel: showsLabel)
    }
}

private struct SoraCheckbox: View {
    let configuration: ToggleStyleConfiguration
    let showsLabel: Bool
    @FocusState private var focused: Bool
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? SoraPalette.accent : SoraPalette.control)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(configuration.isOn || focused ? SoraPalette.accent : hovering ? SoraPalette.border : SoraPalette.inputBorder,
                                lineWidth: 1)
                    LucideIcon("check", size: 12).foregroundStyle(SoraPalette.onAccent)
                        .opacity(configuration.isOn ? 1 : 0)
                        .scaleEffect(configuration.isOn || reduceMotion ? 1 : 0.7)
                }.frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(SoraPalette.accent.opacity(focused ? 0.18 : 0), lineWidth: 3).padding(-2))
                if showsLabel { configuration.label.foregroundStyle(SoraPalette.text) }
            }.frame(minHeight: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focused)
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: configuration.isOn)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: focused)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: hovering)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
            }
    }
}

struct SoraSwitchStyle: ToggleStyle {
    var showsLabel = true
    func makeBody(configuration: Configuration) -> some View {
        SoraSwitch(configuration: configuration, showsLabel: showsLabel)
    }
}

private struct SoraSwitch: View {
    let configuration: ToggleStyleConfiguration
    let showsLabel: Bool
    @FocusState private var focused: Bool
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                if showsLabel { configuration.label.foregroundStyle(SoraPalette.text); Spacer(minLength: 12) }
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? SoraPalette.accent : SoraPalette.elevated)
                    Capsule().strokeBorder(configuration.isOn || focused ? SoraPalette.accent : SoraPalette.inputBorder)
                    Circle().fill(configuration.isOn ? .white : SoraPalette.switchThumb)
                        .frame(width: 18, height: 18).padding(3)
                }.frame(width: 42, height: 24)
                    .clipShape(Capsule())
                    .brightness(hovering && isEnabled ? 0.025 : 0)
                    .overlay(Capsule().stroke(SoraPalette.accent.opacity(focused ? 0.18 : 0), lineWidth: 3).padding(-2))
            }.frame(minHeight: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focused)
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: configuration.isOn)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: focused)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
    }
}
