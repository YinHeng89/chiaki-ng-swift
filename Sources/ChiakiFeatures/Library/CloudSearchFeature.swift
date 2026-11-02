import ChiakiModels
import ComposableArchitecture

/// The full-screen search field the cloud library presents on a compact screen.
///
/// The field edits its own copy of the query and reports every change to the library, which filters the
/// grid behind it while the field is open.
@Reducer public struct CloudSearchFeature {
    /// The text being searched for.
    @ObservableState public struct State: Equatable {
        /// The search text.
        public var query: String

        /// Opens the field on the library's current query.
        ///
        /// - Parameter query: The query the library is filtered by.
        public init(query: String) {
            self.query = query
        }
    }

    /// What the search field can do.
    public enum Action: BindableAction, Equatable {
        /// The field's text changed.
        case binding(BindingAction<State>)
        /// The Clear button was pressed.
        case clearTapped
        /// The Done button was pressed, the query was submitted or the dimmed backdrop was tapped.
        case doneTapped
        /// Tells the library about the query.
        case delegate(Delegate)

        /// What the field reports to the library.
        public enum Delegate: Equatable {
            /// The query changed.
            case queryChanged(String)
        }
    }

    @Dependency(\.dismiss) private var dismiss

    /// Creates the feature.
    public init() {
    }

    /// Reports each edit and dismisses the field when it is done.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                return .send(.delegate(.queryChanged(state.query)))
            case .binding, .delegate:
                return .none
            case .clearTapped:
                state.query = ""
                return .send(.delegate(.queryChanged("")))
            case .doneTapped:
                return .run { [dismiss] _ in
                    await dismiss()
                }
            }
        }
    }
}
