import SwiftUI

struct AnalysisHeader: View {
    let title: String
    let subtitle: String
    @ObservedObject var model: SmartScanModel
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string(title)).font(SoraTypography.body(28, weight: .bold))
                Text(L10n.string(subtitle)).font(SoraTypography.body(13)).foregroundStyle(SoraPalette.secondary)
            }
            Spacer()
            AnalysisActions(model: model)
        }.padding(28)
    }
}

struct AnalysisActions: View {
    @ObservedObject var model: SmartScanModel
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.isScanning || model.isComparing {
                SoraSpinner()
                Text(model.visited.formatted()).monospacedDigit().font(SoraTypography.body(12))
                Button(L10n.text("Detener")) { model.stop() }
            } else {
                Button { model.chooseFolder() } label: { SoraLabel(L10n.text("Elegir carpeta"), icon: "folder-plus") }.disabled(model.busy)
                Button { model.scan() } label: { SoraLabel(L10n.text("Analizar Mac"), icon: "sparkles") }
                    .buttonStyle(SoraButtonStyle(kind: .primary)).disabled(model.busy)
            }
        }.frame(height: 36)
    }
}
