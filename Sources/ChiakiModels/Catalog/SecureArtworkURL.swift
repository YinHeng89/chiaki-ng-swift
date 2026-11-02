import Foundation

extension URL {
    /// Parses an artwork or store address the catalog returned, accepting only plain HTTPS.
    ///
    /// The catalog's text is not trusted: an address that is not HTTPS or that carries a user name or a password
    /// is refused, so nothing is fetched over plain HTTP or with embedded credentials.
    ///
    /// - Parameter raw: The address text, or `nil`.
    /// - Returns: The URL, or `nil` when the text is missing, malformed or not plain HTTPS.
    public static func secureArtwork(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}
