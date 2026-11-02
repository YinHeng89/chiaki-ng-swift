import ChiakiClients
import ComposableArchitecture
import Foundation

/// Presents the settings panel, the console editor and the quit question over the screen, and carries out
/// what they report.
///
/// Only one of them is presented at a time; closing the settings panel tells the settings panes.
struct RootPresentationReducer: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    @Dependency(\.platform) private var platform

    /// Reacts to what is presented over the screen.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard case .destination(let destination) = action else {
                return .none
            }
            return destinationReported(destination, state: &state)
        }
    }

    /// The question asked before the app quits.
    ///
    /// - Parameter origin: What asked to quit.
    /// - Returns: The alert, starting on Cancel.
    static func quitAlert(_ origin: RootFeature.QuitOrigin) -> AlertState<RootFeature.Destination.Alert> {
        AlertState {
            TextState("Quit chiaki-ng?")
        } actions: {
            ButtonState(role: .cancel, action: .stay(origin)) {
                TextState("Cancel")
            }
            ButtonState(role: .destructive, action: .quit) {
                TextState("Quit")
            }
        }
    }

    /// Opens or closes the settings panel, or asks whether to quit.
    ///
    /// - Parameters:
    ///   - view: The request.
    ///   - state: The application's state.
    /// - Returns: The effects of the change.
    func panelRequested(_ view: Action.View, state: inout State) -> Effect<Action> {
        switch view {
        case .openSettings:
            guard state.destination == nil else {
                return .none
            }
            state.destination = .settings
            state.settingsOpenedAt = platform.uptime()
            return .none
        case .closeSettings:
            guard state.settingsPresented else {
                return .none
            }
            state.destination = nil
            state.settingsOpenedAt = nil
            return .send(.settings(.closed))
        case .toggleSettings:
            return state.settingsPresented
                ? panelRequested(.closeSettings, state: &state)
                : panelRequested(.openSettings, state: &state)
        case .quitRequested(let origin):
            guard state.destination == nil else {
                return .none
            }
            state.destination = .alert(Self.quitAlert(origin))
            return .none
        default:
            return .none
        }
    }

    /// Presents the console editor and passes it its first action.
    ///
    /// - Parameters:
    ///   - action: What the editor starts with.
    ///   - state: The application's state.
    /// - Returns: The effect that starts the editor, or none while something else is presented.
    func presentConsoleEditor(_ action: ConsoleEditorFeature.Action,
                              state: inout State) -> Effect<Action> {
        guard state.destination == nil else {
            return .none
        }
        state.destination = .consoleEditor(ConsoleEditorFeature.State())
        return .send(.destination(.presented(.consoleEditor(action))))
    }

    private func destinationReported(
        _ action: PresentationAction<RootFeature.Destination.Action>,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .presented(.consoleEditor(.delegate(.changed))):
            return .send(.consoleCatalog(.load))
        case .presented(.consoleEditor(.delegate(.closed))):
            state.destination = nil
            return .none
        case .presented(.alert(.quit)):
            return .run { [platform] _ in
                await platform.quit()
            }
        case .dismiss:
            guard state.settingsPresented else {
                return .none
            }
            state.settingsOpenedAt = nil
            return .send(.settings(.closed))
        case .presented:
            return .none
        }
    }
}
