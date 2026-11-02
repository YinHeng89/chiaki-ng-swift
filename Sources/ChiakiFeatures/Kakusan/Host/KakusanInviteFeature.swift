import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The host's card for one guest's attempt: the typed reply and code, copying and sharing the invitation, and
/// controller selection.
///
/// The attempt itself lives in ``KakusanHostFeature``, which shows the card for the attempt's current phase
/// with ``State/follow(_:expectations:)``. The card keeps its drafts and passes what the user asks for upward
/// through ``Action/Delegate``.
@Reducer
public struct KakusanInviteFeature {
    /// The card's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The id of the attempt the card shows.
        public let guest: UUID

        /// The reply as typed or pasted.
        public var reply = ""

        /// The guest's code as typed.
        public var code = ""

        /// Whether the invitation was copied since it was shown.
        public internal(set) var copied = false

        /// The invitation, while the attempt waits for a reply.
        public internal(set) var invitation: KakusanBlock?

        /// The invitation as a file to share, once written.
        public internal(set) var shareFile: URL?

        /// The card's controls and the selected one.
        public internal(set) var controls = KakusanControlGrid()

        /// Counts requests to show the on-screen keyboard for the focused field.
        public internal(set) var keyboardRequest = 0

        /// Opens the card for an attempt.
        ///
        /// - Parameter guest: The attempt's id.
        public init(guest: UUID) {
            self.guest = guest
        }

        /// Shows the card for the attempt's current phase.
        ///
        /// - Parameters:
        ///   - phase: Where the attempt is.
        ///   - expectations: The names the host can say the invitation is for.
        public mutating func follow(_ phase: KakusanHostPhase, expectations: [String?]) {
            let grid = KakusanInviteControls.grid(for: phase, expectations: expectations)
            controls.show(grid.rows, preferring: grid.selection)
            if case .invitation(let current, _) = phase {
                if invitation != current.block {
                    copied = false
                    shareFile = nil
                }
                invitation = current.block
            } else {
                invitation = nil
                shareFile = nil
            }
        }
    }

    /// Everything the card reacts to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to the reply or the code.
        case binding(BindingAction<State>)
        /// Something the user did on the card.
        case view(View)
        /// The pasteboard's text arrived.
        case pasted(String?)
        /// The invitation file was written.
        case shareFileReady(URL)
        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did on the card.
        @CasePathable
        public enum View: Equatable, Sendable {
            /// A control was activated.
            case controlActivated(KakusanControl)
            /// Back was pressed.
            case backPressed
            /// Controller navigation moved the selection.
            case moved(KakusanGridStep)
            /// The code field was submitted.
            case codeSubmitted
            /// The invitation's share button appeared.
            case shareShown
        }

        /// What the card asks the host for.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// Say which remembered device the invitation is for; `nil` for a new device.
            case expect(String?)
            /// Import the reply.
            case submitReply(String)
            /// Check the guest's code.
            case submitCode(String)
            /// Cancel the attempt.
            case cancel
            /// Close the card.
            case close
            /// Close the card and create a new invitation.
            case createNew
        }
    }

    private enum CancelID {
        case shareFile
    }

    @Dependency(\.platform) private var platform

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none
            case .view(.moved(let step)):
                state.controls.move(step)
                return .none
            case .view(.controlActivated(let control)):
                state.controls.select(control)
                return activate(control, in: &state)
            case .view(.backPressed):
                return .send(.delegate(.close))
            case .view(.codeSubmitted):
                return .send(.delegate(.submitCode(state.code)))
            case .view(.shareShown):
                guard let invitation = state.invitation, state.shareFile == nil else {
                    return .none
                }
                let name = KakusanBlockFile.name(for: invitation) + "." + KakusanBlockFile.fileExtension
                return .run { [platform] send in
                    await platform.offerFile(invitation.text, name) { url in
                        await send(.shareFileReady(url))
                    }
                }
                .cancellable(id: CancelID.shareFile, cancelInFlight: true)
            case .shareFileReady(let url):
                state.shareFile = url
                return .none
            case .pasted(let text):
                if let text {
                    state.reply = text
                }
                state.controls.select(.connect)
                return .none
            }
        }
    }

    private func activate(_ control: KakusanControl, in state: inout State) -> Effect<Action> {
        switch control {
        case .copy:
            guard let invitation = state.invitation else {
                return .none
            }
            state.copied = true
            return .run { [platform] _ in
                await platform.copy(invitation.text)
            }
        case .paste:
            return .run { [platform] send in
                await send(.pasted(await platform.paste()))
            }
        case .code, .text:
            state.keyboardRequest += 1
            return .none
        case .expect(let name):
            return .send(.delegate(.expect(name)))
        case .connect:
            return .send(.delegate(.submitReply(state.reply)))
        case .verify:
            return .send(.delegate(.submitCode(state.code)))
        case .cancel:
            return .send(.delegate(.cancel))
        case .close:
            return .send(.delegate(.close))
        case .create:
            return .send(.delegate(.createNew))
        case .accept, .back, .remember, .replace, .save, .leave, .name:
            return .none
        }
    }
}
