import SwiftUI

struct SoraInputSurface: ViewModifier {
    var focused = false
    var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(SoraPalette.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(focused && isEnabled ? SoraPalette.accent : hovering && isEnabled ? SoraPalette.border : SoraPalette.inputBorder,
                        lineWidth: focused && isEnabled ? 1.5 : 1))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SoraPalette.accent.opacity(focused && isEnabled ? 0.12 : 0), lineWidth: 3).padding(-2))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: focused)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: hovering)
    }
}

struct SoraTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    @ViewState private var hovering = false

    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(SoraTypography.body(13))
            .foregroundStyle(SoraPalette.text)
            .focused($focused)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .modifier(SoraInputSurface(focused: focused, hovering: hovering))
            .onHover { hovering = $0 }
    }
}

struct SoraSearchField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            LucideIcon("search", size: 15).foregroundStyle(focused ? SoraPalette.accent : SoraPalette.muted)
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused)
                .font(SoraTypography.body(13)).foregroundStyle(SoraPalette.text)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    LucideIcon("x", size: 12).foregroundStyle(SoraPalette.secondary)
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L10n.text("Borrar búsqueda")).accessibilityLabel(L10n.text("Borrar búsqueda"))
            }
        }.padding(.horizontal, 11).frame(height: 36)
            .modifier(SoraInputSurface(focused: focused, hovering: hovering))
            .onHover { hovering = $0 }
    }
}

struct SoraNumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 0) {
            Button { value = min(range.upperBound, value + 1) } label: {
                LucideIcon("chevron-down", size: 11).rotationEffect(.degrees(180))
                    .frame(width: 26, height: 17).contentShape(Rectangle())
            }.disabled(value >= range.upperBound).accessibilityLabel(L10n.text("Aumentar \(title)"))
            SoraDivider()
            Button { value = max(range.lowerBound, value - 1) } label: {
                LucideIcon("chevron-down", size: 11)
                    .frame(width: 26, height: 17).contentShape(Rectangle())
            }.disabled(value <= range.lowerBound).accessibilityLabel(L10n.text("Reducir \(title)"))
        }.buttonStyle(SoraNavigationButtonStyle()).foregroundStyle(SoraPalette.secondary)
            .frame(width: 26, height: 36)
            .modifier(SoraInputSurface())
            .accessibilityElement(children: .contain)
    }
}
