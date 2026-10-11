import SwiftUI
import AppKit

struct SoraTimeField: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let title: String
    @Binding var selection: Date
    @ViewState private var focused = false
    @ViewState private var hovering = false

    var body: some View {
        SoraTimePicker(selection: $selection, focused: $focused, title: title)
            .padding(.horizontal, 11).frame(height: 36)
            .modifier(SoraInputSurface(focused: focused, hovering: hovering))
            .onHover { hovering = $0 }
    }
}

private struct SoraTimePicker: NSViewRepresentable {
    @Binding var selection: Date
    @Binding var focused: Bool
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> TimePicker {
        let picker = TimePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.datePickerMode = .single
        picker.locale = L10n.locale
        picker.drawsBackground = false
        picker.isBezeled = false; picker.isBordered = false
        picker.focusRingType = .none
        picker.font = NSFont(name: "DMSans-9ptRegular_Regular", size: 13) ?? NSFont.systemFont(ofSize: 13)
        picker.setAccessibilityLabel(title)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.change(_:))
        picker.onFocusChange = { [weak coordinator = context.coordinator] value in
            DispatchQueue.main.async { coordinator?.parent.focused = value }
        }
        return picker
    }
    func updateNSView(_ picker: TimePicker, context: Context) {
        context.coordinator.parent = self
        picker.locale = L10n.locale
        picker.setAccessibilityLabel(title)
        if picker.dateValue != selection { picker.dateValue = selection }
        picker.textColor = NSColor(SoraPalette.text)
        picker.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        picker.isEnabled = context.environment.isEnabled
    }
    final class Coordinator: NSObject {
        var parent: SoraTimePicker
        init(parent: SoraTimePicker) { self.parent = parent }
        @objc func change(_ picker: NSDatePicker) { parent.selection = picker.dateValue }
    }
    final class TimePicker: NSDatePicker {
        var onFocusChange: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result { onFocusChange?(true) }
            return result
        }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { onFocusChange?(false) }
            return result
        }
    }
}
