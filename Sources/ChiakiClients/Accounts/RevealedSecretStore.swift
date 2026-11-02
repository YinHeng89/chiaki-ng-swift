import ChiakiModels
import ComposableArchitecture
import Foundation
import Synchronization

/// Holds the one secret the tokens pane has revealed, until the pane hides it.
///
/// The reducer that reveals a secret owns its lifetime: it keeps the secret here under the reveal's
/// `ChiakiModels/OperationID` and discards it when the reveal ends, which wipes the bytes. The view reads
/// the text only for the reveal it is showing, and the secret never enters reducer state.
public final class RevealedSecretStore: Sendable {
    private struct Held: ~Copyable {
        let id: OperationID
        let secret: SecretBytes
    }

    private let held = Mutex<Held?>(nil)

    /// Creates an empty store.
    public init() {}

    /// Keeps a revealed secret, wiping any secret held before.
    ///
    /// - Parameters:
    ///   - secret: The secret.
    ///   - id: The reveal it belongs to.
    public func keep(_ secret: consuming SecretBytes, for id: OperationID) {
        var incoming: Held? = Held(id: id, secret: secret)
        held.withLock { current in
            swap(&current, &incoming)
        }
    }

    /// Wipes the held secret.
    public func discard() {
        var outgoing: Held?
        held.withLock { current in
            swap(&current, &outgoing)
        }
    }

    /// Wipes the held secret when it belongs to a reveal.
    ///
    /// - Parameter id: The reveal whose secret goes.
    public func discard(_ id: OperationID) {
        var outgoing: Held?
        held.withLock { current in
            if current?.id == id {
                swap(&current, &outgoing)
            }
        }
    }

    /// The text of the secret held for a reveal.
    ///
    /// - Parameter id: The reveal being shown.
    /// - Returns: The secret as UTF-8 text, or `nil` when nothing is held for that reveal.
    public func text(for id: OperationID) -> String? {
        held.withLock { current in
            switch current {
            case let .some(held) where held.id == id:
                held.secret.withUnsafeBytes { bytes in
                    String(bytes: bytes, encoding: .utf8) ?? ""
                }
            default:
                nil
            }
        }
    }

    /// Whether a secret is held for a reveal.
    ///
    /// - Parameter id: The reveal.
    /// - Returns: `true` when the store holds that reveal's secret.
    public func holds(_ id: OperationID) -> Bool {
        held.withLock { current in
            current?.id == id
        }
    }
}

extension RevealedSecretStore: Equatable {
    /// Two stores are equal only when they are the same store.
    public static func == (first: RevealedSecretStore, second: RevealedSecretStore) -> Bool {
        first === second
    }
}

extension RevealedSecretStore: TestDependencyKey {
    /// A fresh, empty store for each test.
    public static var testValue: RevealedSecretStore {
        RevealedSecretStore()
    }
}

extension DependencyValues {
    /// Holds the secret the tokens pane has revealed.
    public var revealedSecrets: RevealedSecretStore {
        get {
            self[RevealedSecretStore.self]
        }
        set {
            self[RevealedSecretStore.self] = newValue
        }
    }
}
