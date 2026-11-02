import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Owns the list of the account's PSN conversations shown in the Notifications panel, and the conversation opened
/// from it.
///
/// The listing moves through its own state machine, and every completion carries the operation that started it,
/// so an answer to an older listing never lands.
@Reducer public struct ConversationsFeature {
    /// Where the listing stands.
    public enum Listing: Equatable, Sendable {
        /// Nothing has been asked yet.
        case idle
        /// The operation with this id is asking PSN, showing the conversations listed before meanwhile.
        case loading(UUID)
        /// The conversations are shown.
        case loaded
        /// The last listing failed.
        case failed(PSNMessagesFailure)
    }

    /// The list's state.
    @ObservableState public struct State: Equatable {
        /// The profile whose conversations are listed.
        public let profile: ProfileID
        /// Where the listing stands.
        public var listing = Listing.idle
        /// The conversations, most recently changed first.
        public var conversations: [PSNConversation] = []
        /// The conversation opened from the list.
        @Presents public var conversation: ConversationFeature.State?

        /// Creates the list for a profile.
        ///
        /// - Parameter profile: The profile whose conversations are listed.
        public init(profile: ProfileID) {
            self.profile = profile
        }
    }

    /// Events the list handles.
    public enum Action: Equatable, Sendable {
        /// The list appeared, so the conversations are read when they have not been yet.
        case appeared
        /// The person asked for the list again.
        case refresh
        /// PSN answered the listing started by an operation.
        case listed(UUID, Result<[PSNConversation], PSNMessagesFailure>)
        /// The person opened a conversation.
        case open(String)
        /// The opened conversation acted.
        case conversation(PresentationAction<ConversationFeature.Action>)
    }

    /// Cancellation identifiers for the list's requests.
    public enum CancelID: Hashable, Sendable {
        /// The latest listing.
        case listing
    }

    @Dependency(\.psnMessages) private var client
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard state.listing == .idle else {
                    return .none
                }
                return list(&state)
            case .refresh:
                return list(&state)
            case let .listed(operation, result):
                guard case .loading(operation) = state.listing else {
                    return .none
                }
                switch result {
                case .success(let conversations):
                    state.listing = .loaded
                    state.conversations = conversations
                case .failure(let failure):
                    state.listing = .failed(failure)
                }
                return .none
            case .open(let id):
                guard let chosen = state.conversations.first(where: { $0.id == id }),
                      !chosen.threadID.isEmpty else {
                    return .none
                }
                state.conversation = ConversationFeature.State(
                    profile: state.profile,
                    groupID: chosen.id,
                    threadID: chosen.threadID,
                    title: chosen.title
                )
                return .none
            case .conversation(.dismiss):
                return list(&state)
            case .conversation:
                return .none
            }
        }
        .ifLet(\.$conversation, action: \.conversation) {
            ConversationFeature()
        }
    }

    private func list(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.listing = .loading(operation)
        let profile = state.profile
        return .run { [client] send in
            do throws(PSNMessagesFailure) {
                let conversations = try await client.conversations(profile)
                await send(.listed(operation, .success(conversations)))
            } catch {
                await send(.listed(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.listing, cancelInFlight: true)
    }
}
