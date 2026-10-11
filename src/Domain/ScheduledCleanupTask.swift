import Foundation

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily = "Cada día", weekdays = "De lunes a viernes", weekly = "Una vez por semana"
    var id: String { rawValue }
}

struct CleanupSchedule: Codable, Equatable, Sendable {
    var enabled = false
    var frequency: ScheduleFrequency = .daily
    var hour = 9
    var minute = 30
    var weekday = 2
    var onlyWhenLowSpace = true
    var thresholdGiB = 70
    var generalCaches = true
    var developmentCaches = true
    var dockerCaches = true
    var notifications = true

    func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute), (1...7).contains(weekday), (1...1024).contains(thresholdGiB) else {
            throw ScheduleError.message(L10n.text("Revisa la hora, el día y el umbral de espacio (entre 1 y 1024 GiB)."))
        }
        if enabled && !generalCaches && !developmentCaches && !dockerCaches {
            throw ScheduleError.message(L10n.text("Selecciona al menos una categoría de limpieza antes de activar la tarea."))
        }
    }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
    var dayName: String { [L10n.text("Domingo"), L10n.text("Lunes"), L10n.text("Martes"), L10n.text("Miércoles"), L10n.text("Jueves"), L10n.text("Viernes"), L10n.text("Sábado")][max(1, min(7, weekday)) - 1] }
    var calendarIntervals: [[String: Int]] {
        let time = ["Hour": hour, "Minute": minute]
        switch frequency {
        case .daily: return [time]
        case .weekdays: return (2...6).map { time.merging(["Weekday": $0]) { _, new in new } }
        case .weekly: return [time.merging(["Weekday": weekday]) { _, new in new }]
        }
    }
    var arguments: [String] {
        var result = ["--scheduled", "--no-dialog", "--threshold-gib=\(thresholdGiB)"]
        if !onlyWhenLowSpace { result.append("--always") }
        if !generalCaches { result.append("--skip-general") }
        if !developmentCaches { result.append("--skip-development") }
        if !dockerCaches { result.append("--skip-docker") }
        if !notifications { result.append("--quiet") }
        return result
    }
    func nextRun(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        var after = now
        for _ in 0..<8 {
            var components = DateComponents(hour: hour, minute: minute, second: 0)
            if frequency == .weekly { components.weekday = weekday }
            guard let date = calendar.nextDate(after: after, matching: components, matchingPolicy: .nextTime) else { return nil }
            let day = calendar.component(.weekday, from: date)
            if frequency != .weekdays || (2...6).contains(day) { return date }
            after = date
        }
        return nil
    }
}

enum ScheduleError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct ScheduledCleanupTask: Codable, Equatable, Identifiable, Sendable {
    static let presetID = UUID(uuidString: "0E6AA0B6-1542-4C83-8A05-D4850F99EC21")!
    var id = UUID()
    var name = L10n.text("Nueva limpieza")
    var configuration = CleanupSchedule()
    static var preset: ScheduledCleanupTask { ScheduledCleanupTask(id: presetID, name: L10n.text("Limpieza diaria")) }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ScheduleError.message(L10n.text("Escribe un nombre para la tarea, de hasta 80 caracteres y sin saltos de línea."))
        }
        try configuration.validate()
    }
    var categories: String {
        var names: [String] = []
        if configuration.generalCaches { names.append(L10n.text("Generales")) }
        if configuration.developmentCaches { names.append(L10n.text("Desarrollo")) }
        if configuration.dockerCaches { names.append("Docker") }
        return names.isEmpty ? L10n.text("Sin categorías") : names.joined(separator: " · ")
    }
    var cadence: String {
        (configuration.frequency == .weekly ? L10n.text("\(configuration.dayName), cada semana") : L10n.string(configuration.frequency.rawValue)) + " · " + configuration.timeText
    }
}

struct ScheduleCollection: Codable, Sendable {
    var version = 3
    var tasks: [ScheduledCleanupTask]
    func validate() throws {
        guard [2, 3].contains(version) else { throw ScheduleError.message(L10n.text("Esta versión de la programación no es compatible con Kaze.")) }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw ScheduleError.message(L10n.text("La programación contiene identificadores de tareas repetidos.")) }
        for task in tasks { try task.validate() }
    }
}
