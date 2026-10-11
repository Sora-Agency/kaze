import Foundation

@main
struct LocalizationTests {
    static func main() throws {
        let english = L10n.language == "en"
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message) [\(L10n.language)]")
        }
        check(L10n.preferredLanguage(["es-MX"]) == "es", "Spanish regional variants resolve to Spanish")
        check(L10n.preferredLanguage(["en-GB"]) == "en", "English regional variants resolve to English")
        check(L10n.preferredLanguage(["fr-FR", "es-UY", "en"]) == "es", "First supported preference wins")
        check(L10n.preferredLanguage(["fr-FR"]) == "en", "Unsupported languages fall back to English")
        check(L10n.text("Cancelar") == (english ? "Cancel" : "Cancelar"), "Catalog resolves UI labels")
        let filename = "Informe 100% \"demo\".txt"
        check(L10n.text("Analizando \(filename)…") == (english ? "Scanning \(filename)…" : "Analizando \(filename)…"), "Interpolation preserves arbitrary user filenames")
        check(L10n.count("scan.complete", 1) == (english ? "Scan complete · 1 item" : "Análisis completo · 1 elemento"), "Singular count uses native plural catalog")
        check(L10n.count("scan.complete", 2) == (english ? "Scan complete · 2 items" : "Análisis completo · 2 elementos"), "Plural count uses native plural catalog")
        check(L10n.count("selection.data", 1, arguments: "2 GB") == (english ? "1 data item · 2 GB" : "1 elemento de datos · 2 GB"), "Plural format preserves additional arguments")
        var schedule = CleanupSchedule()
        schedule.frequency = .weekdays
        let json = try JSONEncoder().encode(schedule)
        let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        check(object["frequency"] as? String == "De lunes a viernes", "Persisted schedule values remain compatible across languages")
        check(try JSONDecoder().decode(CleanupSchedule.self, from: json) == schedule, "Schedules round-trip without translation")
        let stored = ScheduledCleanupTask(name: "Mi tarea personal")
        check(stored.name == "Mi tarea personal", "User task names are preserved")
        check(L10n.string(ScheduleFrequency.weekdays.rawValue) == (english ? "Weekdays" : "De lunes a viernes"), "Persisted enum display is translated independently")
        check(L10n.text("Acerca de Kaze") == (english ? "About Kaze" : "Acerca de Kaze"), "App menu is translated")
        check(L10n.locale.language.languageCode?.identifier == L10n.language, "Dates and time fields use the selected language")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("\(L10n.language).lproj"), withIntermediateDirectories: true)
        let terms = directory.appendingPathComponent("\(L10n.language).lproj/TERMS.txt")
        try Data("terms".utf8).write(to: terms)
        check(L10n.document("TERMS.txt", in: directory) == terms, "Legal documents resolve in the selected language")
        check(L10n.document("LICENSE", in: directory) == directory.appendingPathComponent("LICENSE"), "Canonical license remains untranslated")
        print("Localization tests passed.")
    }
}
