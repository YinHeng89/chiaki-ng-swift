import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The PSN account screen: signs in with a QR code another device approves, or opens the web sign-in, shows
/// why the last attempt failed, offers the other method for a new account on a row of tiles, and goes back.
public struct SignInView: View {
    /// The sign-in feature that the buttons drive and whose phase supplies the code and the error message.
    let store: StoreOf<SignInFeature>
    /// The screen's controller focus, shared by every button of the screen.
    let focusedInput: MenuFocusState<EntryFocus?>.Binding
    @Environment(\.screenLayout) private var layout
    @Environment(\.openURL) private var openURL

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - store: The sign-in feature.
    ///   - focusedInput: The screen's focus.
    public init(store: StoreOf<SignInFeature>, focusedInput: MenuFocusState<EntryFocus?>.Binding) {
        self.store = store
        self.focusedInput = focusedInput
    }

    /// The screen.
    public var body: some View {
        VStack(spacing: 0) {
            if !store.acknowledged {
                notice
            } else {
                switch store.method {
                case .qrCode:
                    qrCode
                case .browser:
                    browser
                    FlowTileRow(browserChoices, focusedAction: focusedInput)
                }
            }
        }
        .onAppear {
            store.send(.view(.appeared))
        }
    }

    /// The sign-in code, which a tap opens in the PlayStation app on a touch screen; pointer and controller
    /// users scan it instead, so it is not a focus stop.
    ///
    /// - Parameter approvalURL: The address the code encodes.
    /// - Returns: The code, tappable on touch.
    @ViewBuilder private func signInCode(_ approvalURL: String) -> some View {
        if layout.touch, let destination = URL(string: approvalURL) {
            SwiftUI.Button {
                openURL(destination)
            } label: {
                QRCodeImage(approvalURL, side: codeSide, label: .accountsSignInCodeLabel)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityHint(.accountsSignInCodeHint)
        } else {
            QRCodeImage(approvalURL, side: codeSide, label: .accountsSignInCodeLabel)
        }
    }

    private var shownApprovalURL: String? {
        if case .failed = store.phase {
            return nil
        }
        return store.code?.approvalURL
    }

    private var codeSide: CGFloat {
        layout.isShort
            ? 220
            : 340
    }

    /// The unofficial-client notice with its acknowledgement, the first stage of every sign-in; the sign-in
    /// itself appears once it is ticked.
    private var notice: some View {
        UnofficialClientNotice(footer: {
            EmptyView()
        }, actions: {
            HStack(spacing: 10) {
                FocusButton(.accountsUnofficialUnderstand) {
                    store.send(.view(.acknowledge))
                }
                .glassProminentControlStyle()
                .tint(Palette.accent)
                .foregroundStyle(.black)
                .menuFocused(focusedInput, equals: .acknowledgeUnofficial)
                .accessibilityHint(.accountsUnofficialAcknowledgeHint)
                FocusButton(.commonBack, systemImage: "xmark") {
                    store.send(.view(.back))
                }
                .glassProminentControlStyle()
                .tint(.red)
                .foregroundStyle(.white)
                .menuFocused(focusedInput, equals: .signInBack)
                .accessibilityHint(.accountsSignInBackHint)
            }
        })
        .frame(maxWidth: 460)
        .padding(.bottom, layout.isShort
            ? 12
            : 22)
    }

    /// The code stage: the choices on the left, the code large on the right with the instructions under it.
    private var qrCode: some View {
        HStack(alignment: .center, spacing: 48) {
            FlowTileRow(qrChoices, focusedAction: focusedInput)
                .frame(maxWidth: .infinity)
            VStack(spacing: 14) {
                if let approvalURL = shownApprovalURL {
                    signInCode(approvalURL)
                } else if case .failed = store.phase {
                    Image(systemName: "qrcode")
                        .font(.system(size: codeSide * 0.4))
                        .foregroundStyle(.tertiary)
                        .frame(width: codeSide, height: codeSide)
                } else {
                    ProgressView()
                        .frame(width: codeSide, height: codeSide)
                }
                if case .failed(let failure) = store.phase {
                    message(AccountsFailureMessage.text(for: failure))
                } else if store.code == nil {
                    message(.accountsSignInQrPreparing)
                } else {
                    message(.accountsSignInQrScan)
                }
            }
        }
    }

    /// The tiles under the code: a new code after a failure, the web browser route, and Back.
    private var qrChoices: [FlowTileChoice<EntryFocus>] {
        var choices: [FlowTileChoice<EntryFocus>] = []
        if case .failed = store.phase {
            choices.append(FlowTileChoice(
                label: .accountsSignInNewCode, symbol: "qrcode",
                hint: .accountsSignInNewCodeHint,
                focus: .newSignInCode, prominent: true
            ) {
                store.send(.view(.start))
            })
        }
        choices.append(FlowTileChoice(
            label: .accountsSignInWebBrowser, symbol: "safari",
            hint: .accountsSignInWebBrowserHint,
            focus: .signInOtherMethod
        ) {
            store.send(.view(.choose(.browser)))
        })
        choices.append(backChoice)
        return choices
    }

    @ViewBuilder private var browser: some View {
        message(store.offersQRCode
            ? .accountsSignInBrowserPasskeyUseQr
            : .accountsSignInBrowserPasskeyPageQr)
        if case .failed(let failure) = store.phase {
            message(AccountsFailureMessage.text(for: failure))
        }
    }

    /// The tiles under the web sign-in text: the sign-in itself, the QR code for a new account, and Back.
    private var browserChoices: [FlowTileChoice<EntryFocus>] {
        var choices = [
            FlowTileChoice(
                label: .accountsSignInWithPlayStation, symbol: "safari",
                hint: .accountsSignInWithPlayStationHint,
                focus: EntryFocus.signInWithPlayStation, prominent: true
            ) {
                store.send(.view(.start))
            }
        ]
        if store.offersQRCode {
            choices.append(FlowTileChoice(
                label: .accountsSignInQrCode, symbol: "qrcode",
                hint: .accountsSignInQrCodeHint,
                focus: .signInOtherMethod
            ) {
                store.send(.view(.choose(.qrCode)))
            })
        }
        choices.append(backChoice)
        return choices
    }

    private var backChoice: FlowTileChoice<EntryFocus> {
        FlowTileChoice(
            label: .commonBack, symbol: "arrow.uturn.backward",
            hint: .accountsSignInBackHint,
            focus: .signInBack, cancels: true
        ) {
            store.send(.view(.back))
        }
    }

    private func message(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380)
            .padding(.bottom, 18)
    }
}
