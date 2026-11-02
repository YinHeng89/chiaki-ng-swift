import ChiakiModels
import Foundation

/// A PlayStation Network NPSSO session token with its expiry and where that expiry came from. Its
/// descriptions and mirror redact the token.
struct NPSSOCredential: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// Where a credential's expiry time came from.
    enum ExpirySource: String, Sendable {
        /// No expiry is known, it came from the `npsso` browser cookie, or it came from the token
        /// response.
        case unknown, cookie, tokenResponse = "token_response"
    }
    /// The token, trimmed of surrounding whitespace.
    let value: String
    /// When the token expires, if known.
    let expiresAt: Date?
    /// Where ``NPSSOCredential/expiresAt`` came from.
    let expirySource: ExpirySource
    /// Creates a credential, taking its expiry from a cookie when one is given.
    ///
    /// - Parameters:
    ///   - value: The token, trimmed of surrounding whitespace.
    ///   - cookieExpiresAt: The `npsso` cookie's expiry, or `nil` when unknown.
    init(value: String, cookieExpiresAt: Date? = nil) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expiresAt = cookieExpiresAt
        self.expirySource =
            cookieExpiresAt == nil
                ? .unknown
                : .cookie
    }
    /// Creates a credential with an explicit expiry and source.
    ///
    /// - Parameters:
    ///   - value: The token, trimmed of surrounding whitespace.
    ///   - expiresAt: When the token expires, if known.
    ///   - expirySource: Where the expiry came from.
    init(value: String, expiresAt: Date?, expirySource: ExpirySource) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expiresAt = expiresAt
        self.expirySource = expirySource
    }

    /// Decodes the NPSSO token response, dating the expiry from when the response arrived.
    ///
    /// - Parameters:
    ///   - data: The response body, with `npsso` and an optional `expires_in` in seconds.
    ///   - receivedAt: When the response was received.
    /// - Returns: The credential, with an unknown expiry when the response gives none.
    /// - Throws: `SignInFailure.unreadableResponse` when the token is missing or not cookie-safe,
    ///   or the lifetime is not between one second and ten years.
    static func decodeTokenResponse(_ data: Data, receivedAt: Date) throws(SignInFailure) -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct Payload: Decodable {
            let npsso: String
            let expiresIn: Int?
        }
        guard let payload = try? decoder.decode(Payload.self, from: data),
              !payload.npsso.isEmpty,
              payload.npsso.utf8.allSatisfy({
                  (33...126).contains($0) && ![34, 44, 59, 92].contains($0)
              })
        else {
            throw .unreadableResponse
        }
        guard let lifetime = payload.expiresIn else {
            return .init(value: payload.npsso)
        }
        guard lifetime > 0, lifetime <= 315_360_000 else {
            throw .unreadableResponse
        }
        return .init(
            value: payload.npsso, expiresAt: receivedAt.addingTimeInterval(TimeInterval(lifetime)),
            expirySource: .tokenResponse
        )
    }
    /// Takes the expiry of a matching, unexpired `npsso` cookie when this credential has none.
    ///
    /// - Parameters:
    ///   - cookies: Cookies from the sign-in session.
    ///   - now: The current time.
    /// - Returns: The credential with the cookie's expiry, or this credential unchanged.
    func adoptingCookieExpiry(from cookies: [HTTPCookie], now: Date) -> Self {
        guard expiresAt == nil,
              let expiry = cookies.first(where: { $0.name == "npsso" && $0.value == value })?.expiresDate,
              expiry > now
        else {
            return self
        }
        return .init(value: value, cookieExpiresAt: expiry)
    }
    /// A redacted description that never shows the token.
    var description: String {
        "NPSSOCredential(<redacted>)"
    }
    /// The same redacted text as the description.
    var debugDescription: String {
        description
    }
    /// A mirror that hides the token from dumps and debuggers.
    var customMirror: Mirror {
        Mirror(self, children: ["credential": "<redacted>"])
    }
}
