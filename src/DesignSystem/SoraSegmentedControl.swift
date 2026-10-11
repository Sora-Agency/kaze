import SwiftUI

struct SoraSegmentedControl<Value: Hashable>: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let text: (Value) -> String
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(L10n.string(text(option))).font(SoraTypography.body(12, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? SoraPalette.text : SoraPalette.secondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 7).fill(SoraPalette.control)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(SoraPalette.borderSoft))
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }.contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(SoraNavigationButtonStyle())
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(3).background(SoraPalette.elevated, in: RoundedRectangle(cornerRadius: 10))
            .soraAnimate(selection).accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
