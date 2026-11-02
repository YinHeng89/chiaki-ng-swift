import Synchronization

/// A credential's secret handed over once by the core, held in wiping memory until it is wiped or released.
public final class RevealedSecret: Sendable {
    private let secret: Mutex<SecretBytes?>

    /// Takes ownership of a secret.
    ///
    /// - Parameter secret: The secret, UTF-8 text.
    public init(_ secret: consuming SecretBytes) {
        self.secret = Mutex(secret)
    }

    /// Copies a secret out of a buffer.
    ///
    /// - Parameter source: The secret, UTF-8 text.
    public convenience init(copying source: UnsafeRawBufferPointer) {
        self.init(SecretBytes(count: source.count) { buffer in
            buffer.copyMemory(from: source)
        })
    }

    /// Whether the secret was wiped.
    public var isWiped: Bool {
        secret.withLock { held in
            switch held {
            case .none:
                true
            case .some:
                false
            }
        }
    }

    /// The secret as text, or an empty string once wiped.
    public var text: String {
        secret.withLock { held in
            guard let bytes = held.take() else {
                return ""
            }
            let text = bytes.withUnsafeBytes { buffer in
                String(bytes: buffer, encoding: .utf8) ?? ""
            }
            held = consume bytes
            return text
        }
    }

    /// Moves the secret out, leaving this holder wiped.
    ///
    /// - Returns: The secret, now held only by the returned buffer, or an empty buffer once wiped.
    public func take() -> SecretBytes {
        secret.withLock { held in
            guard let bytes = held.take() else {
                return SecretBytes(count: 0) { _ in
                }
            }
            return bytes
        }
    }

    /// Wipes and releases the secret.
    public func wipe() {
        secret.withLock { held in
            held = nil
        }
    }
}

/// Why a credential's secret was not revealed.
public struct NotRevealed: Error, Hashable, Sendable {
    /// The reasons a reveal is refused.
    public enum Reason: Hashable, Sendable, CaseIterable {
        /// The user does not hold that credential.
        case notHeld

        /// The user has no PSN sign-in.
        case signedOut

        /// The account is not one the core holds.
        case unknownUser

        /// The core is not open.
        case coreClosed
    }

    /// Why the reveal was refused.
    public let reason: Reason

    /// Describes a refusal.
    ///
    /// - Parameter reason: Why the reveal was refused.
    public init(_ reason: Reason) {
        self.reason = reason
    }
}
