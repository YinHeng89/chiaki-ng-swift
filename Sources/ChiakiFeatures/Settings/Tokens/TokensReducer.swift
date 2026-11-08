import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Drives the Tokens settings panel: lists accounts and their credentials, and reveals one credential's
/// secret for a limited time after the device owner authenticates.
@Reducer public struct TokensReducer {
    /// How long a revealed secret stays shown before it is hidden again.
    public static let shownFor = Duration.seconds(30)

    /// The progress of listing the accounts.
    public enum Phase: Equatable, Sendable {
        /// The accounts have not been listed.
        case idle
        /// The listing with this identifier is in flight.
        case loading(UUID)
        /// The accounts are listed.
        case ready
        /// The last listing failed with this message.
        case failed(LocalizedStringResource)
    }

    /// One credential of one account, which can be revealed.
    public struct Target: Equatable, Sendable {
        /// The local identifier of the account.
        public let account: UUID
        /// The kind of credential.
        public let kind: CredentialKind

        /// Identifies the given credential kind of the given account.
        public init(account: UUID, kind: CredentialKind) {
            self.account = account
            self.kind = kind
        }
    }

    /// The reveal workflow for one credential.
    public enum Reveal: Equatable, Sendable {
        /// No credential is revealed.
        case hidden
        /// The reveal with this identifier is authenticating the device owner or reading the secret.
        case authenticating(Target, UUID)
        /// The secret read by the reveal with this identifier is shown.
        case shown(Target, UUID)
        /// The credential could not be revealed, for the reason in this message.
        case refused(Target, LocalizedStringResource)

        /// The identifier of the reveal in flight or shown, or `nil` when there is none.
        public var id: UUID? {
            switch self {
            case .hidden, .refused:
                nil
            case .authenticating(_, let id), .shown(_, let id):
                id
            }
        }

        /// The credential being revealed, shown or refused, or `nil` when hidden.
        public var target: Target? {
            switch self {
            case .hidden:
                nil
            case .authenticating(let target, _), .shown(let target, _), .refused(let target, _):
                target
            }
        }
    }

    /// The listed accounts and the reveal in progress.
    @ObservableState public struct State: Equatable {
        /// The progress of listing the accounts.
        public var phase = Phase.idle
        /// The accounts signed in to PlayStation Network, with their credentials.
        public var accounts: [TokenAccount] = []
        /// Where the reveal workflow stands.
        public var reveal = Reveal.hidden
        /// Whether the device owner authenticated since the panel was last left, so further reveals skip the
        /// prompt.
        public var unlocked = false
        /// The store holding the revealed secret while it is shown, or `nil` when nothing is shown.
        public internal(set) var secrets: RevealedSecretStore?

        /// Creates state with no accounts and nothing revealed.
        public init() {
        }

        /// Whether a reveal is waiting for authentication or for the secret.
        public var authenticating: Bool {
            if case .authenticating = reveal {
                return true
            }
            return false
        }

        /// Whether the accounts are being listed.
        public var busy: Bool {
            if case .loading = phase {
                return true
            }
            return false
        }

        /// Returns whether the target's account is listed and holds the target credential.
        public func holds(_ target: Target) -> Bool {
            accounts.first { $0.id == target.account }?.credentials
                .contains { $0.kind == target.kind && $0.held } ?? false
        }
    }

    /// Events the Tokens panel handles.
    public enum Action: Equatable, Sendable {
        /// Lists the accounts again.
        case load
        /// The listing with this identifier returned these accounts.
        case loaded(UUID, [TokenAccount])
        /// The listing with this identifier failed.
        case failed(UUID)
        /// The user asked to reveal this credential.
        case reveal(Target)
        /// The device owner declined to authenticate for the reveal with this identifier.
        case denied(UUID)
        /// The device owner authenticated for the reveal with this identifier.
        case authenticated(UUID)
        /// The reveal with this identifier kept the secret in the revealed secret store.
        case revealed(UUID)
        /// The reveal with this identifier was refused for this reason.
        case notRevealed(UUID, NotRevealed.Reason)
        /// The display time of the reveal with this identifier ran out.
        case expired(UUID)
        /// The user hid the revealed credential.
        case hide
        /// The panel was left, so authentication is required again and any reveal is hidden.
        case lock
        /// The app resigned active, so a shown secret is hidden.
        case resignedActive
    }

    /// Lists accounts, authenticates and reveals credentials.
    @Dependency(\.accounts) var client
    /// Keeps the revealed secret and wipes it when discarded.
    @Dependency(\.revealedSecrets) var revealedSecrets
    /// Generates the identifiers that tie each completion to its reveal or listing.
    @Dependency(\.uuid) var uuid
    /// Times how long a secret stays shown.
    @Dependency(\.continuousClock) var clock

    /// Identifies the listing and the reveal so a newer one cancels an older one.
    public enum CancelID: Sendable {
        /// The account listing and the credential reveal.
        case accounts, reveal
    }

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                let id = uuid()
                state.phase = .loading(id)
                return .run { [client] send in
                    do {
                        await send(.loaded(id, try await client.tokenAccounts()))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.failed(id))
                    }
                }.cancellable(id: CancelID.accounts, cancelInFlight: true)
            case let .loaded(id, accounts):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.accounts = accounts
                state.phase = .ready
                guard let target = state.reveal.target, !state.holds(target) else {
                    return .none
                }
                return hide(&state)
            case .failed(let id):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.phase = .failed(.settingsTokensAccountsUnreadable)
                return .none
            case let .reveal(target):
                guard state.holds(target),
                      let account = state.accounts.first(where: { $0.id == target.account }) else {
                    return .none
                }
                let id = uuid()
                revealedSecrets.discard()
                state.reveal = .authenticating(target, id)
                return .run { [client, clock, revealedSecrets, unlocked = state.unlocked] send in
                    if !unlocked {
                        let reason = String(localized: .settingsTokensRevealReason)
                        guard await client.authenticateOwner(reason) else {
                            await send(.denied(id))
                            return
                        }
                        await send(.authenticated(id))
                    }
                    guard !Task.isCancelled else {
                        return
                    }
                    switch await client.revealToken(account.accountID, target.kind) {
                    case .success(let secret):
                        guard !Task.isCancelled else {
                            secret.wipe()
                            return
                        }
                        revealedSecrets.keep(secret.take(), for: OperationID(uuid: id))
                        await send(.revealed(id))
                        try? await clock.sleep(for: Self.shownFor)
                        revealedSecrets.discard(OperationID(uuid: id))
                        await send(.expired(id))
                    case .failure(let failure):
                        await send(.notRevealed(id, failure.reason))
                    }
                }.cancellable(id: CancelID.reveal, cancelInFlight: true)
            case .denied(let id):
                guard case .authenticating(_, id) = state.reveal else {
                    return .none
                }
                state.reveal = .hidden
                return .none
            case .authenticated(let id):
                guard case .authenticating(_, id) = state.reveal else {
                    return .none
                }
                state.unlocked = true
                return .none
            case .revealed(let id):
                guard case .authenticating(let target, id) = state.reveal else {
                    return .none
                }
                state.reveal = .shown(target, id)
                state.secrets = revealedSecrets
                return .none
            case let .notRevealed(id, reason):
                guard case .authenticating(let target, id) = state.reveal else {
                    return .none
                }
                state.reveal = .refused(target, reason.message)
                return .none
            case .expired(let id):
                guard case .shown(_, id) = state.reveal else {
                    return .none
                }
                state.reveal = .hidden
                state.secrets = nil
                return .none
            case .hide:
                guard state.reveal != .hidden else {
                    return .none
                }
                return hide(&state)
            case .lock:
                state.unlocked = false
                guard state.reveal != .hidden else {
                    return .none
                }
                return hide(&state)
            case .resignedActive:
                guard case .shown = state.reveal else {
                    return .none
                }
                return hide(&state)
            }
        }
    }

    private func hide(_ state: inout State) -> Effect<Action> {
        revealedSecrets.discard()
        state.reveal = .hidden
        state.secrets = nil
        return .cancel(id: CancelID.reveal)
    }
}
