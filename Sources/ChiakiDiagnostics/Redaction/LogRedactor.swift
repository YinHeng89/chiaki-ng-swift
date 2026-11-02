import ChiakiModels
import CryptoKit
import Foundation

/// The redactor for the log lines and error reports the app writes to disk.
///
/// Log lines keep their shape: identifiers become salted tags such as `[ip#1a2b3c4d]`, so one value maps to the
/// same tag throughout a run without being recoverable, and secrets become ``secretPlaceholder``. API captures
/// are stricter: ``APICaptureRedactor/redact(_:)`` keeps only allow-listed headers, URL parts and JSON scalars.
public struct LogRedactor: Sendable {
    /// Replaces a secret value.
    public static let secretPlaceholder = "[redacted]"

    /// Replaces a JSON web token.
    public static let tokenPlaceholder = "[token]"

    /// Replaces the user's home folder.
    public static let userPlaceholder = "/Users/[user]"

    private let salt: Data

    /// Creates a redactor whose tags are derived from `salt`.
    ///
    /// - Parameter salt: The bytes mixed into every tag.
    public init(salt: Data) {
        self.salt = salt
    }

    /// A redactor with a fresh random salt, so tags differ between runs.
    ///
    /// - Returns: The redactor.
    public static func random() -> Self {
        .init(salt: Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }))
    }

    /// A salted tag for `value`.
    ///
    /// - Parameters:
    ///   - kind: The label shown in the tag.
    ///   - value: The value to hide.
    /// - Returns: `[kind#xxxxxxxx]` with the first four bytes of the salted SHA-256.
    public func tag(_ kind: String, _ value: String) -> String {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(value.utf8))
        let digest = Hex.encode(hasher.finalize().prefix(4))
        return "[\(kind)#\(digest)]"
    }

    /// Redacts one log line.
    ///
    /// - Parameter line: The line to redact.
    /// - Returns: The line with secrets replaced and identifiers tagged.
    public func redact(_ line: String) -> String {
        var text = Self.homePath.replace(in: line) { _, _ in Self.userPlaceholder }
        text = Self.httpAuthorization
            .replace(in: text) { _, groups in "\(groups[1]) \(Self.secretPlaceholder)" }
        text = Self.jsonPair.replace(in: text) { _, groups in
            Self.isSecretKey(groups[1])
                ? "\"\(groups[1])\": \"\(Self.secretPlaceholder)\""
                : nil
        }
        text = Self.assignment.replace(in: text) { _, groups in
            Self.isSecretKey(groups[1])
                ? "\(groups[1])=\(Self.secretPlaceholder)"
                : nil
        }
        text = Self.jwt.replace(in: text) { _, _ in Self.tokenPlaceholder }
        text = Self.mac.replace(in: text) { match, _ in tag("mac", match.lowercased()) }
        text = Self.uuid.replace(in: text) { match, _ in tag("uuid", match.lowercased()) }
        text = Self.ipv4.replace(in: text) { match, _ in redactIPv4(match) }
        text = Self.ipv6.replace(in: text) { match, _ in redactIPv6(match) }
        text = Self.consoleName.replace(in: text) { _, groups in
            groups[1].hasPrefix("[console#")
                ? nil
                : "\"\(tag("console", groups[1]))\" MAC"
        }
        text = Self.decimalID.replace(in: text) { match, _ in tag("id", match) }
        text = Self.hexRun.replace(in: text) { match, _ in
            match.contains(where: \.isLetter)
                ? tag("hex", match.lowercased())
                : nil
        }
        text = Self.blob.replace(in: text) { match, _ in
            Self.looksLikeEncodedBlob(match)
                ? tag("blob", match)
                : nil
        }
        return text
    }

    /// Whether every redaction pattern compiled into a regular expression, so no rule is silently skipped.
    static var patternsCompiled: Bool {
        [
            homePath,
            httpAuthorization,
            jsonPair,
            assignment,
            jwt,
            mac,
            uuid,
            ipv4,
            ipv6,
            consoleName,
            decimalID,
            hexRun,
            blob
        ].allSatisfy {
            $0.regex != nil
        }
    }

    private func redactIPv4(_ address: String) -> String? {
        let octets = address.split(separator: ".").compactMap {
            UInt8($0)
        }
        guard octets.count == 4 else {
            return nil
        }
        if octets == [0, 0, 0, 0] || octets == [255, 255, 255, 255] || octets[0] == 127 {
            return nil
        }
        let privateRange = octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
        return tag(
            privateRange
                ? "lan-ip"
                : "ip",
            address
        )
    }

    private func redactIPv6(_ address: String) -> String? {
        let groups = address.split(separator: ":", omittingEmptySubsequences: false)
        let compressed = address.contains("::")
        guard compressed || groups.count >= 4 else {
            return nil
        }
        if address == "::" || address == "::1" {
            return nil
        }
        return tag("ip6", address.lowercased())
    }

    private static let secretFragments = [
        "token", "npsso", "cookie", "secret", "password", "passwd", "authorization", "authcode", "session",
        "signature", "credential", "apikey", "privatekey", "bearer", "jsessionid", "duid", "refresh"
    ]

    private static let secretExact: Set<String> = ["code", "auth", "sig", "key", "pin", "otp"]

    private static func isSecretKey(_ key: String) -> Bool {
        let normalized = normalizedKey(key)
        return secretExact.contains(normalized) || secretFragments.contains {
            normalized.contains($0)
        }
    }

    /// A key reduced to its lowercase letters and digits, the form the allow-lists and secret names use.
    ///
    /// - Parameter key: The key.
    /// - Returns: The normalised key.
    static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter {
            $0.isLetter || $0.isNumber
        }
    }

    private static func looksLikeEncodedBlob(_ text: String) -> Bool {
        let hasDigit = text.contains(where: \.isNumber)
        let hasUpper = text.contains(where: \.isUppercase)
        let hasLower = text.contains(where: \.isLowercase)
        let budget = text.count / 20
        let slashes = text.filter {
            $0 == "/"
        }.count
        let hyphens = text.filter {
            $0 == "-"
        }.count
        return hasDigit && hasUpper && hasLower && slashes <= budget && hyphens <= budget
    }

    private static let homePath = Pattern(#"/Users/[^/\s"'\[\]\)]+"#)
    private static let httpAuthorization = Pattern(#"\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#)
    private static let jsonPair = Pattern(#""([^"\\]{1,64})"\s*:\s*"([^"\\]*)""#)
    private static let assignment =
        Pattern(#"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_.-]{0,63})=([^\s&;,"'\]\)]+)"#)
    private static let jwt = Pattern(#"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#)
    private static let mac =
        Pattern(#"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}(?![0-9A-Za-z:])"#)
    private static let uuid = Pattern(
        #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
    )
    private static let ipv4 = Pattern(#"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])"#)
    private static let ipv6 =
        Pattern(#"(?<![0-9A-Za-z:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![0-9A-Za-z:.])"#)
    private static let consoleName = Pattern(#""([^"]{1,64})" MAC\b"#)
    private static let decimalID = Pattern(#"(?<![0-9A-Za-z.#])\d{16,20}(?![0-9A-Za-z.])"#)
    private static let hexRun = Pattern(#"(?<![0-9A-Za-z#])(?:0x)?[0-9A-Fa-f]{12,}(?![0-9A-Za-z])"#)
    private static let blob =
        Pattern(#"(?<![A-Za-z0-9+/=_#-])[A-Za-z0-9+/_-]{40,}={0,2}(?![A-Za-z0-9+/=_-])"#)

    private struct Pattern: @unchecked Sendable {
        let regex: NSRegularExpression?

        init(_ pattern: String) {
            regex = try? NSRegularExpression(pattern: pattern)
        }

        func replace(in text: String, with replacement: (String, [String]) -> String?) -> String {
            let whole = NSRange(text.startIndex..., in: text)
            guard let matches = regex?.matches(in: text, range: whole), !matches.isEmpty else {
                return text
            }
            var result = ""
            var cursor = text.startIndex
            for match in matches {
                guard let range = Range(match.range, in: text) else {
                    continue
                }
                let groups = (0..<match.numberOfRanges).map { index in
                    Range(match.range(at: index), in: text).map {
                        String(text[$0])
                    } ?? ""
                }
                guard let replaced = replacement(groups[0], groups) else {
                    continue
                }
                result += text[cursor..<range.lowerBound]
                result += replaced
                cursor = range.upperBound
            }
            result += text[cursor...]
            return result
        }
    }
}
