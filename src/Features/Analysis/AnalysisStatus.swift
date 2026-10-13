import SwiftUI

struct AnalysisStatusStrip: View {
    @ObservedObject var model: SmartScanModel
    @ViewState private var details = false
    private var warning: Bool { model.isStale || model.index.partial || model.catalog == nil || model.error != nil }
    var body: some View {
        HStack(spacing: 8) {
            LucideIcon(warning ? "circle-alert" : "shield-check", size: 13)
                .foregroundStyle(warning ? Color.orange : SoraPalette.success)
            Text(L10n.string(model.isRestoring ? "Recuperando análisis…" : model.catalog == nil ? "Firma no verificada" : model.showingCached ? "Análisis guardado" : model.isStale ? "Vuelve a analizar" : model.index.partial ? "Análisis parcial" : model.error != nil ? "Revisa el análisis" : model.index.files.isEmpty ? "Sin analizar" : "Análisis disponible"))
                .font(SoraTypography.body(11, weight: .medium))
            if !model.index.files.isEmpty {
                Text("· " + L10n.date(model.index.date, includeTime: true))
                    .font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { details.toggle() } label: { SoraLabel(L10n.text("Detalles del análisis"), icon: "info") }
                .font(SoraTypography.body(10)).buttonStyle(.plain).foregroundStyle(SoraPalette.secondary)
                .accessibilityLabel(L10n.text("Detalles del análisis"))
                .popover(isPresented: $details) { AnalysisNotice(model: model).frame(width: 510).padding(.vertical, 8) }
        }.padding(.horizontal, 24).padding(.vertical, 9)
    }
}

struct AnalysisNotice: View {
    @ObservedObject var model: SmartScanModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.index.files.isEmpty { Text(L10n.text("Análisis del \(L10n.date(model.index.date, includeTime: true))")) }
            if !model.index.files.isEmpty { Text(L10n.text("Tamaño lógico: \(formatDiskBytes(model.index.logical))")) }
            Text(L10n.text("Espacio para revisar muestra lo que ocupan apps, proyectos y archivos; requiere decidir qué conservar. No se suma a la recuperación potencial."))
            if model.showingCached { Text(L10n.text("Resultados de la última sesión. Vuelve a analizar para comprobar cambios antes de limpiar.")) }
            else if model.isStale { Text(L10n.text("El disco cambió desde este análisis. Vuelve a analizar antes de limpiar.")) }
            if let error = model.error { Text(error).foregroundStyle(Color.orange).textSelection(.enabled) }
            if model.index.partial { Text(L10n.text("Análisis parcial: hay rutas protegidas, inaccesibles o fuera del límite. No se cuentan como espacio recuperable.")) }
            if model.index.omitted > 0 {
                Text(L10n.text("Los tamaños incluyen todos los metadatos accesibles. El mapa conserva hasta 250.000 detalles; abre una carpeta en el Explorador para ver los restantes."))
            }
            if model.catalog == nil { Text(L10n.text("No se pudo verificar la firma de las reglas. La limpieza está bloqueada.")) }
            Text(L10n.text("Recuperación potencial tras vaciar la Papelera: APFS puede conservar clones y snapshots. El tamaño lógico no equivale a espacio liberado."))
        }.font(SoraTypography.body(11)).foregroundStyle(SoraPalette.secondary).padding(.horizontal, 28).padding(.vertical, 12)
    }
}
