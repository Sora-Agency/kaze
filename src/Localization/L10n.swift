import Foundation

enum L10n {
    struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Hashable {
        let key: String
        let arguments: [String]

        init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        init(stringInterpolation: Interpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct Interpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            init(literalCapacity: Int, interpolationCount: Int) {
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) {
                key += literal.replacingOccurrences(of: "%", with: "%%")
            }

            mutating func appendInterpolation<Value>(_ value: Value) {
                key += "%@"
                arguments.append(String(describing: value))
            }
        }
    }

    static func preferredLanguage(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: ["en", "es"], forPreferences: preferences).first ?? "en"
    }

    static let preferenceKey = "kaze.language"
    static let languageDidChange = Notification.Name("kaze.languageDidChange")
    private static let languageLock = NSLock()
    private static var selectedLanguage = initialLanguage()

    static func initialLanguage(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let language = environment["KAZE_LANGUAGE"], AppLanguage(rawValue: language) != nil {
            return language
        }
        if let language = defaults.string(forKey: preferenceKey), AppLanguage(rawValue: language) != nil {
            return language
        }
        let preferences = defaults.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return preferredLanguage(preferences)
    }

    static var language: String {
        languageLock.lock()
        defer { languageLock.unlock() }
        return selectedLanguage
    }

    static func select(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: preferenceKey)
        languageLock.lock()
        let changed = selectedLanguage != language.rawValue
        selectedLanguage = language.rawValue
        languageLock.unlock()
        if changed { NotificationCenter.default.post(name: languageDidChange, object: nil) }
    }

    static var locale: Locale {
        Locale(identifier: language + "_" + (Locale.current.region?.identifier ?? "US"))
    }

    static let resources: URL? = {
        if let path = ProcessInfo.processInfo.environment["KAZE_LOCALIZATION_RESOURCES"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL
    }()

    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
        guard let directory = resources?.appendingPathComponent(language.rawValue + ".lproj"),
              let bundle = Bundle(url: directory) else { return nil }
        return (language.rawValue, bundle)
    })

    static func string(_ key: String) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    static func text(_ message: Message) -> String {
        let format = string(message.key)
        guard !message.arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: message.arguments.map { $0 as CVarArg })
    }

    static func count(_ key: String, _ count: Int, arguments: String...) -> String {
        String(format: string(key), locale: locale, arguments: [count as CVarArg] + arguments.map { $0 as CVarArg })
    }

    static func date(_ date: Date, includeTime: Bool = false) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: includeTime ? .shortened : .omitted).locale(locale))
    }

    static func document(_ filename: String, in directory: URL) -> URL {
        let localized = directory.appendingPathComponent(language + ".lproj/" + filename)
        return FileManager.default.fileExists(atPath: localized.path) ? localized : directory.appendingPathComponent(filename)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }
    var name: String { self == .spanish ? "Español" : "English" }
}

enum LocalizedText: Hashable {
    case message(L10n.Message)
    case count(String, Int)
    case verbatim(String)

    var string: String {
        switch self {
        case .message(let message): return L10n.text(message)
        case .count(let key, let count): return L10n.count(key, count)
        case .verbatim(let value): return value
        }
    }
}
