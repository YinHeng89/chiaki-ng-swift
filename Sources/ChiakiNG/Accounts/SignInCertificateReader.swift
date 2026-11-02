import ChiakiModels
import CryptoKit
import Foundation
import Security

/// Reads the leaf certificate of a secured connection into a `ChiakiModels/SignInCertificate`.
///
/// The subject, organisation, issuer and validity come from the certificate's parsed fields on macOS; on
/// other platforms only the subject summary and the fingerprint are read.
enum SignInCertificateReader {
    /// Describes the certificate a connection was secured with.
    ///
    /// - Parameters:
    ///   - trust: The connection's evaluated server trust.
    ///   - host: The host the page was loaded from.
    /// - Returns: The leaf certificate, or `nil` when the trust holds none.
    static func certificate(of trust: SecTrust, host: String) -> SignInCertificate? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return nil
        }
        let data = SecCertificateCopyData(leaf) as Data
        let fingerprint = SHA256.hash(data: data).map { byte in
            String(format: "%02X", byte)
        }.joined(separator: " ")
        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? host
        let fields = Fields(of: leaf)
        return SignInCertificate(
            host: host,
            subject: subject,
            organization: fields.organization,
            location: fields.location,
            issuer: fields.issuer,
            validFrom: fields.validFrom,
            validUntil: fields.validUntil,
            fingerprint: fingerprint
        )
    }

    private struct Fields {
        var organization: String?
        var location: String?
        var issuer: String?
        var validFrom: Date?
        var validUntil: Date?

        init(of certificate: SecCertificate) {
            #if os(macOS)
                guard let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: [String: Any]]
                else {
                    return
                }
                let subject = Self.entries(values[kSecOIDX509V1SubjectName as String])
                let issuer = Self.entries(values[kSecOIDX509V1IssuerName as String])
                organization = subject[kSecOIDOrganizationName as String]
                let place = [
                    subject[kSecOIDLocalityName as String],
                    subject[kSecOIDStateProvinceName as String],
                    subject[kSecOIDCountryName as String]
                ].compactMap { $0 }
                location = place.isEmpty
                    ? nil
                    : place.joined(separator: ", ")
                self.issuer = issuer[kSecOIDCommonName as String] ?? issuer[kSecOIDOrganizationName as String]
                validFrom = Self.date(values[kSecOIDX509V1ValidityNotBefore as String])
                validUntil = Self.date(values[kSecOIDX509V1ValidityNotAfter as String])
            #endif
        }

        private static func entries(_ section: [String: Any]?) -> [String: String] {
            guard let items = section?[kSecPropertyKeyValue as String] as? [[String: Any]] else {
                return [:]
            }
            var found: [String: String] = [:]
            for item in items {
                if let label = item[kSecPropertyKeyLabel as String] as? String,
                   let value = item[kSecPropertyKeyValue as String] as? String {
                    found[label] = value
                }
            }
            return found
        }

        private static func date(_ entry: [String: Any]?) -> Date? {
            guard let seconds = entry?[kSecPropertyKeyValue as String] as? Double else {
                return nil
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
    }
}
