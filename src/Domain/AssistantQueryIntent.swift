import Foundation

enum AssistantQueryIntent {
    case greeting, information, fileActions

    static func detect(_ question: String) -> Self {
        let text = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
        let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init)
        let greetings = ["hola", "hola kaze", "hello", "hello kaze", "hi", "hi kaze", "hey", "buenas", "buen dia", "buenos dias", "buenas tardes", "buenas noches"]
        if greetings.contains(words.joined(separator: " ")) { return .greeting }
        guard !words.contains(where: { ["no", "not", "never", "don't", "dont", "nunca"].contains($0) }) else { return .information }
        let verbs = ["borr", "elimin", "limpi", "vaci", "revis", "administr", "gestion", "desinstal", "libera", "mov", "papelera",
                     "clean", "delet", "remov", "trash", "reclaim", "review", "manage", "uninstall"]
        return words.contains(where: { word in verbs.contains { word.hasPrefix($0) } }) ? .fileActions : .information
    }
}
