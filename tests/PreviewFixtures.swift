import Foundation

enum PreviewFixtures {
    static let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
    static let storage = StorageSnapshot(total: 512_000_000_000, free: 164_000_000_000)

    static func entries(in folder: URL) -> [FileEntry] {
        let examples: [(String, Int64, Bool)] = folder.lastPathComponent == "Library"
            ? [("Application Support", 8_400_000_000, true), ("Caches", 3_200_000_000, true),
               ("Developer", 1_600_000_000, true), ("Preferences", 240_000_000, true),
               ("Logs", 48_000_000, true), ("Fonts", 12_000_000, true)]
            : [("Vídeo de ejemplo.mov", 6_400_000_000, false), ("Recursos de diseño", 2_100_000_000, true),
               ("Fotos de ejemplo", 1_300_000_000, true), ("Instalador de ejemplo.dmg", 690_000_000, false),
               ("Recursos.zip", 380_000_000, false), ("Presentación.pdf", 12_000_000, false),
               ("Notas.txt", 32_000, false)]
        let englishNames = ["Example video.mov", "Design assets", "Example photos", "Example installer.dmg",
                            "Assets.zip", "Presentation.pdf", "Notes.txt"]
        let classifier = DeletionClassifier(home: home)
        return examples.enumerated().map { index, example in
            let name = L10n.language == "en" && folder.lastPathComponent != "Library" ? englishNames[index] : example.0
            let url = folder.appendingPathComponent(name, isDirectory: example.2)
            return FileEntry(url: url, isDirectory: example.2, isSymbolicLink: false,
                             modified: Date(timeIntervalSince1970: 1_791_417_600 - Double(index * 86_400)),
                             measurement: DiskMeasurement(bytes: example.1), deletion: classifier.assess(url))
        }
    }
}
