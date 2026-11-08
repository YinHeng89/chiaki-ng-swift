import Foundation

/// A pasted `RCP1:` invitation or reply block; its text never appears in descriptions or mirrors.
public struct KakusanBlock: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// What a block carries, read from its first decoded byte.
    public enum Kind: Equatable, Sendable {
        /// A host's invitation.
        case invitation

        /// A guest's reply.
        case reply

        /// Something else.
        case unrecognised
    }

    /// The prefix every block starts with.
    public static let prefix = "RCP1:"

    /// The longest text accepted from the pasteboard before whitespace is removed.
    public static let maximumPastedLength = 131_072

    /// The longest block accepted.
    public static let maximumLength = 98304

    /// The first decoded byte of a block that carries a host's invitation.
    static let invitationHead: UInt8 = 0x51
    /// The first decoded byte of a block that carries a guest's reply.
    static let replyHead: UInt8 = 0x52

    /// The block with whitespace removed.
    public let text: String

    /// What the block carries.
    public var kind: Kind {
        var encoded = text.dropFirst(Self.prefix.count)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        switch Data(base64Encoded: encoded)?.first {
        case Self.invitationHead:
            return .invitation
        case Self.replyHead:
            return .reply
        default:
            return .unrecognised
        }
    }

    /// Reads a pasted block, removing whitespace.
    ///
    /// - Parameter pasted: The pasted text; refused when too long, without the prefix or not base64url.
    public init?(pasted: String) {
        guard pasted.count <= Self.maximumPastedLength else {
            return nil
        }
        let ignored: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]
        let compact = String(String.UnicodeScalarView(pasted.unicodeScalars.filter {
            !ignored.contains($0)
        }))
        let trimmed = compact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.prefix), trimmed.utf8.count <= Self.maximumLength else {
            return nil
        }
        let payload = trimmed.utf8.dropFirst(Self.prefix.utf8.count)
        guard !payload.isEmpty, payload.allSatisfy(Self.isBase64URL) else {
            return nil
        }
        text = trimmed
    }

    private static func isBase64URL(_ byte: UInt8) -> Bool {
        switch byte {
        case 48 ... 57, 65 ... 90, 97 ... 122, 45, 95:
            true
        default:
            false
        }
    }

    /// Always `[REDACTED]`.
    public var description: String {
        "[REDACTED]"
    }

    /// Always `[REDACTED]`.
    public var debugDescription: String {
        "[REDACTED]"
    }

    /// A mirror with no children, so reflection reveals nothing.
    public var customMirror: Mirror {
        Mirror(self, children: [])
    }
}

/// What to tell the user when a pasted block is not the kind that was asked for.
public enum KakusanBlockAdvice {
    /// The advice for text pasted where a reply was expected.
    ///
    /// - Parameter pasted: The pasted text.
    /// - Returns: The advice.
    public static func reply(_ pasted: String) -> LocalizedStringResource {
        KakusanBlock(pasted: pasted)?.kind == .invitation
            ? .kakusanAdviceInvitationNotReply
            : .kakusanAdviceIncompleteReply
    }

    /// The advice for text pasted where an invitation was expected.
    ///
    /// - Parameter pasted: The pasted text.
    /// - Returns: The advice.
    public static func invitation(_ pasted: String) -> LocalizedStringResource {
        KakusanBlock(pasted: pasted)?.kind == .reply
            ? .kakusanAdviceReplyNotInvitation
            : .kakusanAdviceIncompleteInvitation
    }
}
