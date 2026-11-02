import ComposableArchitecture
import Foundation

/// Runs the screen shown by ``RootFeature`` and moves between screens.
///
/// Each screen with work of its own runs that work under a cancel id, so ``show(_:state:)`` cancels it when
/// the screen is left, and releases discovery when the add-console screen goes away.
struct RootRouter: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    private enum CancelID: Hashable {
        case signIn
        case accountIDEntry
        case addConsole
        case pairing
    }

    /// Runs the shown screen's reducer for its actions.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard case .route(let child) = action else {
                return .none
            }
            let effect = RootFeature.Route.body._reduce(into: &state.route, action: child).map(Action.route)
            guard let id = Self.cancelID(state.route) else {
                return effect
            }
            return effect.cancellable(id: id)
        }
    }

    /// Shows a screen, cancelling the work of the screen it replaces.
    ///
    /// - Parameters:
    ///   - route: The screen to show.
    ///   - state: The application's state.
    /// - Returns: The effects that stop the replaced screen's work.
    static func show(_ route: RootFeature.Route.State, state: inout State) -> Effect<Action> {
        let leaving = cancelID(state.route)
        let leavingAddConsole = state.route.is(\.addConsole) && !route.is(\.addConsole)
        state.route = route
        state.registrationFailure = nil
        var effects: [Effect<Action>] = []
        if let leaving, leaving != cancelID(route) {
            effects.append(.cancel(id: leaving))
        }
        if leavingAddConsole {
            effects.append(.send(.discovery(.release(.addConsole))))
        }
        return .merge(effects)
    }

    /// Returns home from the stream screen.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The effects of leaving, or none when the stream screen is not shown.
    static func leaveStream(state: inout State) -> Effect<Action> {
        guard state.route == .stream else {
            return .none
        }
        return show(state.home, state: &state)
    }

    /// Returns home once a guest join is no longer shown.
    ///
    /// - Parameters:
    ///   - presented: Whether the guest join is shown.
    ///   - state: The application's state.
    /// - Returns: The effects of leaving the guest screen.
    static func followGuest(_ presented: Bool, state: inout State) -> Effect<Action> {
        guard !presented, state.route.is(\.kakusanGuest) else {
            return .none
        }
        return show(state.home, state: &state)
    }

    private static func cancelID(_ route: RootFeature.Route.State) -> CancelID? {
        switch route {
        case .signIn:
            .signIn
        case .accountIDEntry:
            .accountIDEntry
        case .addConsole:
            .addConsole
        case .pairing:
            .pairing
        case .launching, .welcome, .library, .stream, .kakusanGuest:
            nil
        }
    }
}
