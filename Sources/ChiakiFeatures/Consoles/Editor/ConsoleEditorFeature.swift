import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Edits or deletes one console, following `ChiakiModels/ConsoleEditFlow`.
///
/// A deletion asked for from the editor keeps the draft: withdrawing it, or a failed deletion, returns to the
/// editor with every change. A failed save returns to the editor too. Each read, save and deletion carries
/// the `ChiakiModels/OperationID` that started it. The parent is told about a finished change through
/// ``Action/Delegate/changed`` and reloads its catalog.
@Reducer
public struct ConsoleEditorFeature {
    /// The editor's state.
    @ObservableState
    public struct State: Equatable {
        /// Where the edit is.
        public internal(set) var flow = ConsoleEditFlow.closed

        /// Creates the state with no console being edited.
        public init() {}

        /// Whether nothing is being edited, confirmed or saved.
        public var isClosed: Bool {
            flow == .closed
        }
    }

    /// Everything the editor reacts to.
    public enum Action: Equatable {
        /// Opens the editor for a console.
        case edit(ConsoleDraft)

        /// Asks to delete a console from the library.
        case requestDeletion(UUID)

        /// Something the user did.
        case view(View)

        /// The console's options were read, or could not be.
        case optionsLoaded(OperationID, Result<ConsoleLaunchOptions, ConsoleEditFailure>)

        /// A save or deletion finished, with why it failed.
        case finished(OperationID, ConsoleEditFailure?)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// Changes the name.
            case setName(String)

            /// Changes the address.
            case setAddress(String)

            /// Changes whether the console connects at launch.
            case setConnectAtLaunch(Bool)

            /// Forgets the saved login PIN when the edit is saved.
            case forgetLoginPIN

            /// Asks to delete the console being edited.
            case delete

            /// Saves the draft, or deletes the console waiting for confirmation.
            case confirm

            /// Steps back: withdraws a confirmation, dismisses a failure, or closes the editor.
            case cancel
        }

        /// What the editor reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// A console was saved or deleted.
            case changed

            /// The editor closed: nothing is edited, confirmed or saved any more.
            case closed
        }
    }

    @Dependency(\.consoles) private var client
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            let wasClosed = state.isClosed
            let effect = handle(action, state: &state)
            guard !wasClosed, state.isClosed else {
                return effect
            }
            return .concatenate(effect, .send(.delegate(.closed)))
        }
    }

    private func handle(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case .edit(let draft):
            let id = OperationID(uuid: uuid())
            guard state.flow.open(draft, id: id) else {
                return .none
            }
            return .run { [client] send in
                await send(.optionsLoaded(id, client.launchOptions(draft.id)))
            }
        case .requestDeletion(let console):
            state.flow.requestDeletion(of: console)
            return .none
        case let .optionsLoaded(id, .success(options)):
            state.flow.loaded(options, id: id)
            return .none
        case let .optionsLoaded(id, .failure(failure)):
            state.flow.finish(id, failure: failure)
            return .none
        case let .finished(id, failure):
            guard state.flow.finish(id, failure: failure) else {
                return .none
            }
            return failure == nil
                ? .send(.delegate(.changed))
                : .none
        case .view(let view):
            return reduce(&state, view: view)
        case .delegate:
            return .none
        }
    }

    private func reduce(_ state: inout State, view: Action.View) -> Effect<Action> {
        switch view {
        case .setName(let name):
            state.flow.edit {
                $0.name = name
            }
        case .setAddress(let address):
            state.flow.edit {
                $0.address = address
            }
        case .setConnectAtLaunch(let enabled):
            state.flow.edit {
                $0.connectAtLaunch = enabled
            }
        case .forgetLoginPIN:
            state.flow.edit {
                if $0.loginPIN == .saved {
                    $0.loginPIN = .forgotten
                }
            }
        case .delete:
            if let draft = state.flow.draft {
                state.flow.requestDeletion(of: draft.id)
            }
        case .cancel:
            state.flow.cancel()
        case .confirm:
            return confirm(&state)
        }
        return .none
    }

    private func confirm(_ state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        guard state.flow.confirm(id) else {
            return .none
        }
        switch state.flow {
        case .saving(_, let draft):
            return .run { [client] send in
                await send(.finished(id, client.saveDraft(draft)))
            }
        case .deleting(_, let console, _):
            return .run { [client] send in
                await send(.finished(id, client.deleteConsole(console)))
            }
        case .closed, .loading, .editing, .confirmingDeletion, .failed:
            return .none
        }
    }
}
