import SwiftUI
import QuickLookUI

private struct FileQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

extension View {
    func kazeQuickLook(_ url: Binding<URL?>) -> some View {
        sheet(isPresented: Binding(get: { url.wrappedValue != nil }, set: { if !$0 { url.wrappedValue = nil } })) {
            if let selected = url.wrappedValue {
                VStack(spacing: 0) {
                    HStack { Text(selected.lastPathComponent).font(SoraTypography.body(14, weight: .semibold)); Spacer()
                        Button(L10n.text("Cerrar")) { url.wrappedValue = nil } }.padding(16)
                    FileQuickLook(url: selected).frame(minWidth: 640, minHeight: 480)
                }.background(SoraPalette.main)
            }
        }
    }
}
