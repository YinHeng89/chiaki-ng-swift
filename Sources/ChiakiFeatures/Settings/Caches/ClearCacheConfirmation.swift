import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus

/// Asks before a cache is cleared.
@Reducer
public struct ClearCacheConfirmation {
    /// What would be cleared.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The cache, or all caches.
        public let clearing: CacheClearing

        /// Asks about clearing.
        ///
        /// - Parameter clearing: The cache, or all caches.
        public init(_ clearing: CacheClearing) {
            self.clearing = clearing
        }

        /// The prompt shown.
        public var confirmation: AppConfirmation {
            clearing.confirmation
        }
    }

    /// The user's answer.
    public enum Action: Equatable, Sendable {
        /// Clear.
        case confirm

        /// Keep the cache.
        case cancel
    }

    @Dependency(\.dismiss) private var dismiss

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .confirm:
                return .none
            case .cancel:
                return .run { [dismiss] _ in
                    await dismiss()
                }
            }
        }
    }
}
