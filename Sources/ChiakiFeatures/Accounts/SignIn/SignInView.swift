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
            switch store.method {
            case .qrCode:
                qrCode
                FlowTileRow(qrChoices, focusedAction: focusedInput)
            case .browser:
                browser
                FlowTileRow(browserChoices, focusedAction: focusedInput)
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
                QRCodeImage(approvalURL, side: 220, label: .accountsSignInCodeLabel)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityHint(.accountsSignInCodeHint)
        } else {
            QRCodeImage(approvalURL, side: 220, label: .accountsSignInCodeLabel)
        }
    }

    /// The unofficial-client notice with its acknowledgement, which every sign-in must tick first.
    private var notice: some View {
        UnofficialClientNotice {
            UnofficialClientAcknowledgement(acknowledged: store.acknowledged, focusedInput: focusedInput) {
                store.send(.view(.acknowledge))
            }
        }
        .frame(maxWidth: 460)
        .padding(.bottom, layout.isShort
            ? 12
            : 22)
    }

    @ViewBuilder private var qrCode: some View {
        notice
        FlowTitle(text: .accountsSignInTitle, detail: .accountsSignInQrDetail)
        if case .failed(let failure) = store.phase {
            message(AccountsFailureMessage.text(for: failure))
        } else if let code = store.code {
            message(store.acknowledged
                ? .accountsSignInQrScan
                : .accountsSignInQrTickFirst)
            signInCode(code.approvalURL)
                .blur(radius: store.acknowledged
                    ? 0
                    : 10)
                    .allowsHitTesting(store.acknowledged)
                    .accessibilityHidden(!store.acknowledged)
                    .animation(.easeOut(duration: 0.2), value: store.acknowledged)
                    .padding(.bottom, 8)
        } else {
            ProgressView()
                .controlSize(.small)
                .padding(.bottom, 10)
            message(.accountsSignInQrPreparing)
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
        notice
        FlowTitle(text: .accountsSignInTitle, detail: .accountsSignInBrowserDetail)
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
                label: .accountsSignInWithPlayStation, symbol: "arrow.up.right",
                hint: store.acknowledged
                    ? .accountsSignInWithPlayStationHint
                    : .accountsSignInTickFirst,
                focus: EntryFocus.signInWithPlayStation, prominent: true, enabled: store.acknowledged
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
