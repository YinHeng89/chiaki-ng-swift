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

    /// Whether the title shows above the tiles; the touch welcome shows the logo beside them instead.
    var showsTitle = true

    /// The view.
    var body: some View {
        if showsTitle {
            FlowTitle(text: "Add your account.", detail: "Choose how to get started.")
        }
        FlowTileRow(choices, focusedAction: focusedAction)
    }

    /// The tiles, left to right: the PSN sign-in first, then the account id route, then joining a game and
    /// returning to the profiles when those apply.
    private var choices: [FlowTileChoice<String>] {
        var choices = [
            FlowTileChoice(
                label: "PSN account", symbol: "person.crop.circle.badge.checkmark",
                hint: "Sign in with your phone or email. PSN features such as play outside your home network "
                    + "and cloud games are enabled.",
                focus: "PSN account", prominent: true
            ) {
                send(.chooseSignIn)
            },
            FlowTileChoice(
                label: "Base64 PSN ID", symbol: "person.text.rectangle",
                hint: "No PSN features will be enabled, such as external network play.",
                focus: "Base64 PSN ID profile"
            ) {
                send(.chooseAccountID)
            },
        ]
        if KakusanBuild.included {
            choices.append(FlowTileChoice(
                label: "Join a game", symbol: "person.2.wave.2",
                hint: "Join a friend's game from the invitation they sent you.",
                focus: "Join a game"
            ) {
                send(.joinGame)
            })
        }
        if hasProfiles {
            choices.append(FlowTileChoice(
                label: "Back to profiles", symbol: "arrow.uturn.backward",
                hint: "Return to the accounts you already added.",
                focus: "Back to profiles", cancels: true
            ) {
                send(.showLibrary)
            })
        }
        return choices
    }
}
