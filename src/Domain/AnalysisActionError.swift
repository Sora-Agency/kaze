import Foundation

enum AnalysisActionError: LocalizedError {
    case changed, rule, originalChanged, pendingTrash, inUse([String])
    var errorDescription: String? {
        switch self {
        case .pendingTrash: return L10n.text("Finder aún no confirmó el traslado. Revisa la Papelera; el resultado queda pendiente de verificar.")
        case .changed: return L10n.text("El elemento cambió o no se pudo verificar; vuelve a analizar.")
        case .rule: return L10n.text("No hay una regla verificada que permita esta acción.")
        case .originalChanged: return L10n.text("La copia conservada cambió o ya no coincide; se conserva la selección.")
        case .inUse(let names): return L10n.text("Cierra estos procesos antes de limpiar: \(names.joined(separator: ", "))")
        }
    }
}
