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

extension PreviewFixtures {
    static func analysisIndex(long: Bool = false) -> StorageIndex {
        let date = Date(timeIntervalSince1970: 1_791_800_000)
        var index = StorageIndex(date: date, roots: [home], home: home, files: [], children: [:], byPath: [:])
        @discardableResult
        func add(_ path: String, parent: Int?, directory: Bool, bytes: Int64, logical: Int64? = nil, protected: Bool = false) -> Int {
            let url = home.appendingPathComponent(path, isDirectory: directory)
            let position = index.files.count
            var file = IndexedFile(url: url, parent: parent, directory: directory, symbolicLink: false, protected: protected,
                fingerprint: FileFingerprint(device: 1, inode: UInt64(position + 1), size: logical ?? bytes, modified: 1_791_800_000, nanoseconds: 0),
                links: 1, ownAllocated: bytes, logical: logical ?? bytes, allocated: bytes, modified: date)
            file.systemKind = AnalysisProtection.systemKind(url, home: home)
            file.potentialAllocated = protected ? 0 : bytes; file.containsProtected = protected
            index.files.append(file); index.children[parent ?? -1, default: []].append(position); index.byPath[url.path] = position
            return position
        }
        let root = add("", parent: nil, directory: true, bytes: 0)
        let library = add("Library", parent: root, directory: true, bytes: 0)
        let dev = add("Library/Developer", parent: library, directory: true, bytes: 0)
        let xcode = add("Library/Developer/Xcode", parent: dev, directory: true, bytes: 0)
        add("Library/Developer/Xcode/DerivedData", parent: xcode, directory: true, bytes: 7_800_000_000)
        let caches = add("Library/Caches", parent: library, directory: true, bytes: 0)
        add("Library/Caches/com.google.Chrome", parent: caches, directory: true, bytes: 850_000_000)
        add("Library/Caches/pip", parent: caches, directory: true, bytes: 1_200_000_000)
        let support = add("Library/Application Support", parent: library, directory: true, bytes: 0)
        add("Library/Application Support/Example App", parent: support, directory: true, bytes: 4_100_000_000)
        add("Library/Logs", parent: library, directory: true, bytes: 380_000_000)
        let downloads = add("Downloads", parent: root, directory: true, bytes: 0)
        add("Downloads/Example installer.dmg", parent: downloads, directory: false, bytes: 4_000_000_000)
        let documents = add("Documents", parent: root, directory: true, bytes: 0)
        add("Documents/Example installer copy.dmg", parent: documents, directory: false, bytes: 4_000_000_000)
        add("Documents/Project archive.zip", parent: documents, directory: false, bytes: 5_200_000_000)
        let projects = add("Projects", parent: root, directory: true, bytes: 0)
        let project = add("Projects/Example", parent: projects, directory: true, bytes: 0)
        add("Projects/Example/package.json", parent: project, directory: false, bytes: 4096)
        add("Projects/Example/node_modules", parent: project, directory: true, bytes: 3_200_000_000)
        let npm = add(".npm", parent: root, directory: true, bytes: 0)
        add(".npm/_cacache", parent: npm, directory: true, bytes: 1_850_000_000)
        let ollama = add(".ollama", parent: root, directory: true, bytes: 0)
        add(".ollama/models", parent: ollama, directory: true, bytes: 12_500_000_000)
        let apps = add("Applications", parent: root, directory: true, bytes: 0)
        add("Applications/Example.app", parent: apps, directory: true, bytes: 2_100_000_000)
        add("Pictures", parent: root, directory: true, bytes: 8_200_000_000)
        if long {
            for number in 1...24 {
                add("Documents/Archive-\(number).zip", parent: documents, directory: false, bytes: 200_000_000 + Int64(number) * 1_000_000)
            }
            for number in 1...4 {
                let extra = add("Projects/Example-\(number)", parent: projects, directory: true, bytes: 0)
                add("Projects/Example-\(number)/package.json", parent: extra, directory: false, bytes: 4096)
                add("Projects/Example-\(number)/node_modules", parent: extra, directory: true, bytes: 450_000_000)
            }
        }
        for position in index.files.indices.reversed() {
            if let parent = index.files[position].parent {
                index.files[parent].allocated += index.files[position].allocated
                index.files[parent].logical += index.files[position].logical
                index.files[parent].potentialAllocated += index.files[position].potentialAllocated
            }
        }
        for i in index.files.indices where index.files[i].directory {
            if let kind = index.files[i].systemKind, index.files[i].parent.map({ index.files[$0].systemKind != kind }) ?? true {
                index.systemLocations[kind, default: []].append(i)
            }
        }
        index.scannedCount = 28_420
        index.systemTotals = [.caches: AnalysisBytes(logical: 9_850_000_000, allocated: 9_850_000_000),
            .support: AnalysisBytes(logical: 4_100_000_000, allocated: 4_100_000_000),
            .logs: AnalysisBytes(logical: 380_000_000, allocated: 380_000_000)]
        return index
    }
}
