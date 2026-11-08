import ChiakiModels
import MenuFocus
import SwiftUI

/// The welcome screen: a row of tiles to sign in with a PSN account, add an account by account id, join a game
/// when this build has Kakusan, or return to the library when an account already exists.
struct WelcomeView: View {
    /// Whether an account exists, so the library can be returned to.
    let hasProfiles: Bool

    /// The screen's action focus.
    let focusedAction: MenuFocusState<String?>.Binding

    /// Sends what the user chose to the root.
    let send: (RootFeature.Action.View) -> Void

    /// The view: the choices alone, beside the logo the entry screen draws.
    var body: some View {
        FlowTileRow(choices, focusedAction: focusedAction)
    }

    /// The tiles, left to right: the PSN sign-in first, then the account id route, then joining a game and
    /// returning to the profiles when those apply.
    private var choices: [FlowTileChoice<String>] {
        var choices = [
            FlowTileChoice(
                label: .accountsWelcomePsnAccount, symbol: "person.crop.circle.badge.checkmark",
                hint: .accountsWelcomePsnAccountHint,
                focus: "PSN account", prominent: true
            ) {
                send(.chooseSignIn)
            },
            FlowTileChoice(
                label: .accountsWelcomeAccountId, symbol: "person.text.rectangle",
                hint: .accountsWelcomeAccountIdHint,
                focus: "Base64 PSN ID profile"
            ) {
                send(.chooseAccountID)
            },
        ]
        if KakusanBuild.included {
            choices.append(FlowTileChoice(
                label: .accountsWelcomeJoinGame, symbol: "person.2.wave.2",
                hint: .accountsWelcomeJoinGameHint,
                focus: "Join a game"
            ) {
                send(.joinGame)
            })
        }
        if hasProfiles {
            choices.append(FlowTileChoice(
                label: .accountsWelcomeBackToProfiles, symbol: "arrow.uturn.backward",
                hint: .accountsWelcomeBackToProfilesHint,
                focus: "Back to profiles", cancels: true
            ) {
                send(.showLibrary)
            })
        }
        return choices
    }
}
