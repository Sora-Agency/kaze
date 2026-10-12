import Foundation

struct LocalAIAsset {
    let url: URL
    let bytes: Int64
    let sha256: String
    let filename: String
}

struct LocalAIPackage {
    let version: String
    let engine: LocalAIAsset
    let model: LocalAIAsset
    let engineFolder: String
    var downloadBytes: Int64 { engine.bytes + model.bytes }
    static let modelRevision = "23749fefcc72300e3a2ad315e1317431b06b590a"
    static let modelLicense = URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/blob/\(modelRevision)/LICENSE")!
    static var supported: Bool { ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 3, patchVersion: 0)) }
    static let bundled: LocalAIPackage = {
        #if arch(arm64)
        let architecture = "arm64"
        let engineSize: Int64 = 11_095_544
        let engineHash = "533f546dab2ce2f8e29ce3070f26acc55acc59528e177f2cd0d52b7f69b44f50"
        #else
        let architecture = "x64"
        let engineSize: Int64 = 11_401_963
        let engineHash = "968669b2ec00acf9804e325b51180014d09939894202d44206b4a190d9ef0369"
        #endif
        return LocalAIPackage(version: "qwen3-06b-b10566-\(architecture)",
            engine: LocalAIAsset(url: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b10566/llama-b10566-bin-macos-\(architecture).tar.gz")!,
                bytes: engineSize, sha256: engineHash, filename: "engine.tar.gz"),
            model: LocalAIAsset(url: URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/\(modelRevision)/Qwen3-0.6B-Q8_0.gguf")!,
                bytes: 639_446_688, sha256: "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031", filename: "model.gguf"),
            engineFolder: "llama-b10566")
    }()
}

enum LocalAIError: LocalizedError, Equatable {
    case integrity, download, unsupported, space, notInstalled, cancelled, engine, timeout
    var errorDescription: String? {
        switch self {
        case .integrity: return L10n.text("No se pudo verificar la IA local. Vuelve a descargarla.")
        case .download: return L10n.text("No se pudo completar la descarga. Comprueba la conexión e inténtalo otra vez.")
        case .unsupported: return L10n.text("La IA local requiere macOS 13.3 o posterior.")
        case .space: return L10n.text("Necesitas al menos 1,5 GB libres para descargar y preparar la IA local.")
        case .notInstalled: return L10n.text("Descarga la IA local para consultar al asistente.")
        case .cancelled: return L10n.text("Operación cancelada. Puedes volver a intentarlo cuando quieras.")
        case .engine: return L10n.text("El motor local no pudo generar una respuesta. Puedes seguir revisando Smart Scan.")
        case .timeout: return L10n.text("La consulta tardó demasiado y se detuvo. Prueba con una pregunta más corta.")
        }
    }
}
