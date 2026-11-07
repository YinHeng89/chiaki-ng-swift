import ChiakiModels
import Foundation
import Observation

/// The language chiaki-ng shows: the system's, or one the app has a translation for.
///
/// The choice is stored as the app's `AppleLanguages` preference, which the system reads when the app opens,
/// so a new choice takes effect at the next launch.
@MainActor
@Observable
final class AppLanguageSetting {
    /// A language choice.
    enum Choice: Hashable, Sendable {
        /// Follow the system's language order.
        case system
        /// One translation, by its language identifier, such as `en`.
        case language(String)
    }

    private static let key = "AppleLanguages"

    /// The language identifiers the app has translations for, in the order they are offered.
    let supported: [String]

    /// The choice that was in effect when the app opened.
    let launched: Choice

    /// The current choice.
    private(set) var choice: Choice

    private let defaults: UserDefaults

    /// Reads the current choice.
    ///
    /// - Parameters:
    ///   - defaults: Where the preference is stored.
    ///   - domain: The app's preference domain, which tells a choice made in the app from the system's order.
    ///   - bundle: The bundle whose translations are offered.
    init(
        defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier,
        bundle: Bundle = .module
    ) {
        self.defaults = defaults
        supported = bundle.localizations.filter { $0 != "Base" }.sorted()
        let stored = domain
            .flatMap { defaults.persistentDomain(forName: $0)?[Self.key] as? [String] }?
            .first
            .flatMap { identifier in
                bundle.localizations.contains(identifier)
                    ? identifier
                    : nil
            }
        let current = stored.map(Choice.language) ?? .system
        choice = current
        launched = current
    }

    /// The choices in the order they are offered: the system's language first.
    var choices: [Choice] {
        [.system] + supported.map(Choice.language)
    }

    /// Whether the app must open again to show the current choice.
    var needsRelaunch: Bool {
        choice != launched
    }

    /// Stores a new choice.
    ///
    /// - Parameter choice: The language to show from the next launch.
    func choose(_ choice: Choice) {
        self.choice = choice
        switch choice {
        case .system:
            defaults.removeObject(forKey: Self.key)
        case .language(let identifier):
            defaults.set([identifier], forKey: Self.key)
        }
    }

    /// The name of a choice: "System" in the app's language, or the language's own name for itself.
    ///
    /// - Parameter choice: The choice.
    /// - Returns: Its name.
    static func title(_ choice: Choice) -> LocalizedStringResource {
        switch choice {
        case .system:
            .settingsInterfaceLanguageSystem
        case .language(let identifier):
            .verbatim(Self.nativeName(of: identifier))
        }
    }

    private static func nativeName(of identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        let name = locale.localizedString(forIdentifier: identifier) ?? identifier
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}
