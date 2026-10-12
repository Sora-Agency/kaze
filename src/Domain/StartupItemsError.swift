import Foundation

enum StartupItemsError: Error, CustomStringConvertible {
    case invalidApplication, missingApplication, unconfirmed, oversizedStore, tooManyItems, permission, automation

    var description: String {
        switch self {
        case .invalidApplication: return L10n.text("Solo se pueden modificar aplicaciones de inicio.")
        case .missingApplication: return L10n.text("La aplicación ya no está instalada en esa ubicación.")
        case .unconfirmed: return L10n.text("macOS no confirmó el cambio. Vuelve a cargar la lista.")
        case .oversizedStore: return L10n.text("El registro de apps al inicio supera el límite de lectura.")
        case .tooManyItems: return L10n.text("Hay demasiados elementos de inicio para mostrarlos.")
        case .permission: return L10n.text("Permite que Kaze controle Eventos del Sistema en Ajustes → Privacidad y seguridad → Automatización.")
        case .automation: return L10n.text("No se pudieron actualizar las apps al inicio. Comprueba el permiso de Automatización y vuelve a cargar la lista.")
        }
    }
}
