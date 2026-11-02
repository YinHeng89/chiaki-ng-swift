import Foundation

/// What the sign-in page's server proved about itself: the certificate its connection was secured with.
///
/// The sign-in screen shows it above the page so the person can see whose page they are typing their password
/// into. Only the leaf certificate is described.
public struct SignInCertificate: Hashable, Sendable {
    /// The host the page was loaded from.
    public let host: String

    /// The certificate's subject, usually the host name it was issued to.
    public let subject: String

    /// The organisation the certificate was issued to, when it names one.
    public let organization: String?

    /// Where the organisation is, as the certificate states it, such as a city, region and country.
    public let location: String?

    /// The authority that issued the certificate, when it is known.
    public let issuer: String?

    /// When the certificate became valid, when it is known.
    public let validFrom: Date?

    /// When the certificate stops being valid, when it is known.
    public let validUntil: Date?

    /// The SHA-256 fingerprint of the certificate, as upper-case hex pairs separated by spaces.
    public let fingerprint: String

    /// Describes a certificate.
    ///
    /// - Parameters:
    ///   - host: The host the page was loaded from.
    ///   - subject: The certificate's subject.
    ///   - organization: The organisation it was issued to, if named.
    ///   - location: Where the organisation is, if stated.
    ///   - issuer: The issuing authority, if known.
    ///   - validFrom: When it became valid, if known.
    ///   - validUntil: When it stops being valid, if known.
    ///   - fingerprint: Its SHA-256 fingerprint as hex pairs.
    public init(
        host: String,
        subject: String,
        organization: String? = nil,
        location: String? = nil,
        issuer: String? = nil,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        fingerprint: String
    ) {
        self.host = host
        self.subject = subject
        self.organization = organization
        self.location = location
        self.issuer = issuer
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.fingerprint = fingerprint
    }

    /// The organisation and its location on one line, or `nil` when the certificate names no organisation.
    public var verifiedParty: String? {
        guard let organization else {
            return nil
        }
        guard let location else {
            return organization
        }
        return "\(organization), \(location)"
    }
}
