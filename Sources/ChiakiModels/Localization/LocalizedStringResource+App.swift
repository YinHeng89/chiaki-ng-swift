import Foundation

extension LocalizedStringResource {
    /// Text shown exactly as given in every language: a name, a message from a server, or text another part of
    /// the app has already localized.
    ///
    /// - Parameter text: The text to show.
    /// - Returns: A resource that resolves to `text` in every locale.
    public static func verbatim(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource("\(text)")
    }

    /// The text in English, for logs and reports that stay readable to the developers whatever language the
    /// app shows.
    public var english: String {
        var english = self
        english.locale = Locale(identifier: "en")
        return String(localized: english)
    }
}
