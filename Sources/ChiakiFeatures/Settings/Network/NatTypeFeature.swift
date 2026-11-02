import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The Network settings' NAT type check.
///
/// A check moves from idle to checking and on to a type or a failure; its answer carries the operation that asked,
/// so an answer after the page closed or a newer check began is dropped.
@Reducer public struct NatTypeFeature {
    /// Where the check stands.
    public enum Check: Equatable, Sendable {
        /// No check has run.
        case idle
        /// The operation with this id is checking.
        case checking(UUID)
        /// The check found this type.
        case found(NatType)
        /// The check could not tell the type.
        case failed(NatTypeFailure)
    }

    /// The check's state.
    @ObservableState public struct State: Equatable, Sendable {
        /// Where the check stands.
        public var check = Check.idle

        /// Creates an idle check.
        public init() {
        }

        /// Whether a check is running.
        public var isChecking: Bool {
            guard case .checking = check else {
                return false
            }
            return true
        }
    }

    /// What the check can do.
    public enum Action: Equatable, Sendable {
        /// The player asked to check.
        case checkTapped
        /// The check started by an operation finished.
        case checked(UUID, Result<NatType, NatTypeFailure>)
        /// The page closed, so a running check ends.
        case stopped
    }

    /// Cancellation identifiers for the check.
    public enum CancelID: Sendable {
        /// The running check.
        case check
    }

    /// Runs the check.
    @Dependency(\.network) var diagnostics
    /// Generates operation identifiers.
    @Dependency(\.uuid) var uuid

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .checkTapped:
                guard !state.isChecking else {
                    return .none
                }
                let operation = uuid()
                state.check = .checking(operation)
                return .run { [diagnostics] send in
                    do throws(NatTypeFailure) {
                        let type = try await diagnostics.natType()
                        await send(.checked(operation, .success(type)))
                    } catch {
                        await send(.checked(operation, .failure(error)))
                    }
                }
                .cancellable(id: CancelID.check, cancelInFlight: true)
            case let .checked(operation, result):
                guard case .checking(operation) = state.check else {
                    return .none
                }
                switch result {
                case .success(let type):
                    state.check = .found(type)
                case .failure(let failure):
                    state.check = .failed(failure)
                }
                return .none
            case .stopped:
                if state.isChecking {
                    state.check = .idle
                }
                return .cancel(id: CancelID.check)
            }
        }
    }
}
