import Foundation
import Combine

final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()
    @Published private(set) var selection: AppLanguage
    private let defaults: UserDefaults
    private var subscription: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage(rawValue: L10n.language) ?? .english
        subscription = NotificationCenter.default.publisher(for: L10n.languageDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let language = AppLanguage(rawValue: L10n.language), language != self.selection else { return }
                self.selection = language
            }
    }

    var locale: Locale { L10n.locale }

    @MainActor
    func select(_ language: AppLanguage) {
        L10n.select(language, defaults: defaults)
        selection = language
    }
}
