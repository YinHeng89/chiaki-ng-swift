import ChiakiModels
import ComposableArchitecture
import Foundation

/// Finds the console to pair: from the local-network scan, by typed address, or from the PSN account.
///
/// The typed address is validated by `ChiakiModels/ConsoleAddress`, the one console-address validator. The
/// PSN console list is a presented ``AccountConsolesFeature`` while the PlayStation mode is chosen. The scan
/// itself belongs to the root's ``DiscoveryFeature``; this feature asks for it through
/// ``Action/Delegate/startScanning`` and ``Action/Delegate/stopScanning``, and reports the chosen console
/// with ``Action/Delegate/pair(_:)``.
@Reducer public struct AddConsoleFeature {
    /// What the user chose and typed on the screen, kept while a pairing attempt runs.
    public struct Draft: Equatable, Sendable {
        /// The chosen mode.
        public let mode: AddConsoleMode

        /// The typed address.
        public let address: String

        /// The generation of the console at the typed address.
        public let kind: RegistrationFlow.ConsoleKind

        /// Creates a draft.
        ///
        /// - Parameters:
        ///   - mode: The chosen mode.
        ///   - address: The typed address.
        ///   - kind: The generation of the console at the typed address.
        public init(mode: AddConsoleMode, address: String, kind: RegistrationFlow.ConsoleKind) {
            self.mode = mode
            self.address = address
            self.kind = kind
        }
    }

    /// The screen's fields and chosen mode.
    @ObservableState public struct State: Equatable {
        /// The account the console is paired for.
        public let account: UUID

        /// The modes the account may use, in display order.
        public let modes: [AddConsoleMode]

        /// The chosen mode.
        public internal(set) var mode: AddConsoleMode

        /// The typed address.
        public var address = ""

        /// The generation of the console at the typed address.
        public var kind = RegistrationFlow.ConsoleKind.ps5

        /// The account's paired consoles, which the lists leave out.
        public let registered: [RegistrationFlow.ConsoleTarget]

        /// The PSN console list, while the PlayStation mode is chosen.
        @Presents public var accountConsoles: AccountConsolesFeature.State?

        /// Opens the screen.
        ///
        /// - Parameters:
        ///   - account: The account the console is paired for.
        ///   - modes: The modes the account may use; the first is chosen unless `preferred` is allowed.
        ///   - preferred: The mode to open on, such as PlayStation after an internet pairing failed.
        ///   - registered: The account's paired consoles.
        ///   - draft: What the user chose and typed before a pairing attempt, restored on return; `preferred`
        ///     still wins over its mode.
        public init(
            account: UUID,
            modes: [AddConsoleMode],
            preferred: AddConsoleMode? = nil,
            registered: [RegistrationFlow.ConsoleTarget] = [],
            draft: Draft? = nil
        ) {
            self.account = account
            self.modes = modes.isEmpty
                ? [.manual]
                : modes
            self.registered = registered
            mode = (preferred ?? draft?.mode).flatMap { preferred in
                modes.contains(preferred)
                    ? preferred
                    : nil
            } ?? self.modes[0]
            if let draft {
                address = draft.address
                kind = draft.kind
            }
        }

        /// What the user chose and typed, to restore after a pairing attempt.
        public var draft: Draft {
            Draft(mode: mode, address: address, kind: kind)
        }

        /// The typed address, when it is valid.
        public var validAddress: ConsoleAddress? {
            ConsoleAddress(address)
        }

        /// The discovered consoles that are not paired with the account yet.
        ///
        /// - Parameter snapshot: What the scan sees.
        /// - Returns: The consoles not matching a paired console by hardware id, or by address for a console
        ///   paired without one.
        public func unpaired(in snapshot: DiscoverySnapshot) -> [DiscoveredConsole] {
            snapshot.consoles.filter { discovered in
                !registered.contains { paired in
                    if let hardwareID = paired.hardwareID {
                        return Self.hexDigits(hardwareID) == Self.hexDigits(discovered.id)
                    }
                    return paired.remoteDeviceID == nil && paired.address == discovered.address
                }
            }
        }

        private static func hexDigits(_ value: String) -> String {
            value.lowercased().filter(\.isHexDigit)
        }
    }

    /// Everything the screen reacts to.
    public enum Action: BindableAction, Equatable {
        /// A change to a bound field.
        case binding(BindingAction<State>)

        /// Something the user did.
        case view(View)

        /// The presented PSN console list.
        case accountConsoles(PresentationAction<AccountConsolesFeature.Action>)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// The screen appeared.
            case appeared

            /// The screen went away.
            case disappeared

            /// Chooses how to find the console.
            case selectMode(AddConsoleMode)

            /// Pairs the console at the typed address.
            case submitAddress

            /// Pairs a console the scan found.
            case pickDiscovered(DiscoveredConsole)

            /// Starts a failed scan again.
            case retryScan

            /// Leaves the screen.
            case back
        }

        /// What the screen reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The screen needs the local-network scan.
            case startScanning

            /// The screen no longer needs the scan.
            case stopScanning

            /// The scan failed and should start again.
            case retryScanning

            /// The user chose this console to pair.
            case pair(RegistrationFlow.ConsoleTarget)

            /// The user left.
            case left
        }
    }

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none
            case .view(.appeared):
                return enter(state.mode, state: &state)
            case .view(.disappeared):
                state.accountConsoles = nil
                return .send(.delegate(.stopScanning))
            case .view(.selectMode(let mode)):
                guard state.modes.contains(mode), mode != state.mode else {
                    return .none
                }
                let leaving: Effect<Action> = state.mode == .automatic
                    ? .send(.delegate(.stopScanning))
                    : .none
                state.mode = mode
                return .concatenate(leaving, enter(mode, state: &state))
            case .view(.submitAddress):
                guard let address = state.validAddress else {
                    return .none
                }
                return .send(.delegate(.pair(.init(address: address.text, kind: state.kind))))
            case .view(.pickDiscovered(let console)):
                return .send(.delegate(.pair(.init(
                    address: console.address,
                    kind: console.kind == .ps5
                        ? .ps5
                        : .ps4
                ))))
            case .view(.retryScan):
                return .send(.delegate(.retryScanning))
            case .view(.back):
                return .send(.delegate(.left))
            case .accountConsoles(.presented(.delegate(.selected(let target)))):
                return .send(.delegate(.pair(target)))
            case .accountConsoles:
                return .none
            }
        }
        .ifLet(\.$accountConsoles, action: \.accountConsoles) {
            AccountConsolesFeature()
        }
    }

    private func enter(_ mode: AddConsoleMode, state: inout State) -> Effect<Action> {
        switch mode {
        case .automatic:
            state.accountConsoles = nil
            return .send(.delegate(.startScanning))
        case .manual:
            state.accountConsoles = nil
            return .none
        case .playStation:
            guard state.accountConsoles == nil else {
                return .none
            }
            state.accountConsoles = AccountConsolesFeature.State(
                accountID: state.account,
                excludedDeviceIDs: Set(state.registered.compactMap(\.remoteDeviceID))
            )
            return .send(.accountConsoles(.presented(.load)))
        }
    }
}
