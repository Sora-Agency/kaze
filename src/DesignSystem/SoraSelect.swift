import SwiftUI

struct SoraSelect<Value: Hashable>: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let text: (Value) -> String
    @ViewState private var hovering = false
    @ViewState private var expanded = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(L10n.string(text(selection))).lineLimit(1)
                Spacer(minLength: 4)
                LucideIcon("chevron-down", size: 14).foregroundStyle(SoraPalette.muted)
            }.font(SoraTypography.body(12)).foregroundStyle(SoraPalette.text)
                .padding(.horizontal, 11).frame(height: 36)
                .modifier(SoraInputSurface(focused: expanded, hovering: hovering))
        }.buttonStyle(.plain)
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(spacing: 3) {
                    ForEach(options, id: \.self) { option in
                        Button { selection = option; expanded = false } label: {
                            HStack(spacing: 10) {
                                Text(L10n.string(text(option))).font(SoraTypography.body(12))
                                Spacer(minLength: 12)
                                LucideIcon("check", size: 14).opacity(option == selection ? 1 : 0)
                            }.foregroundStyle(option == selection ? SoraPalette.accent : SoraPalette.text)
                                .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(SoraNavigationButtonStyle())
                    }
                }.padding(8).frame(minWidth: 190).background(SoraPalette.surface)
                    .onExitCommand { expanded = false }
            }
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : SoraMotion.interaction, value: hovering)
            .accessibilityLabel(title).accessibilityValue(L10n.string(text(selection)))
    }
}
