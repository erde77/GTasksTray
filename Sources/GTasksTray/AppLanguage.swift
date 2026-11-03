import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case polish = "pl"

    static let preferenceKey = "appLanguage"

    static var systemDefault: Self {
        Locale.preferredLanguages.first?.split(separator: "-").first == "pl" ? .polish : .english
    }

    static var saved: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? systemDefault
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .english: "English"
        case .polish: "Polski"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .polish ? "pl_PL" : "en")
    }

    private static let polishBundle: Bundle? = {
        let path = Bundle.main.path(forResource: "pl", ofType: "lproj")
            ?? Bundle.module.path(forResource: "pl", ofType: "lproj")
        return path.flatMap(Bundle.init(path:))
    }()

    func text(_ key: String) -> String {
        guard self == .polish else { return key }
        return Self.polishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

protocol AppLocalizedError: LocalizedError {
    func message(in language: AppLanguage) -> String
}

extension AppLocalizedError {
    var errorDescription: String? { message(in: .saved) }
}

struct AppMessage: AppLocalizedError {
    let key: String

    init(_ key: String) { self.key = key }

    func message(in language: AppLanguage) -> String { language.text(key) }
}
