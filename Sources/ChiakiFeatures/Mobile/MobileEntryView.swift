import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// Welcome, PSN sign-in and the Base64 PSN ID profile on a touch screen, each laid out side by side on one
/// screen without scrolling, with Back in the same floating rail the library uses.
///
/// Both screens draw the root's and the sign-in feature's state and send their actions; the unofficial-client
/// notice is a sheet shown while the sign-in has not been acknowledged.
struct MobileEntryView: View {
    /// The root.
    let store: StoreOf<RootFeature>

    /// Sends a choice to the root.
    let send: (RootFeature.Action.View) -> Void

    @Environment(\.screenLayout) private var layout
    @Environment(\.libraryRailEdge) private var railEdge
    @MenuFocusState private var focusedAction: String?
    @MenuFocusState private var focusedInput: EntryFocus?

    var body: some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mobileSwipeBack(enabled: back != nil) {
                back?()
            }
            .overlay(alignment: railAlignment) {
                if let back {
                    MobileEntryRail(edge: railEdge, back: back)
                        .padding(railInsets)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let signIn = store.scope(state: \.route.signIn, action: \.route.signIn) {
            MobileSignInView(store: signIn, focusedInput: $focusedInput)
        } else if let entry = store.scope(state: \.route.accountIDEntry, action: \.route.accountIDEntry) {
            MobileAccountIDView(store: entry, failure: store.accounts.operation.failure)
        } else {
            welcome
        }
    }

    @ViewBuilder private var welcome: some View {
        if layout.sideBySide {
            HStack(spacing: 40) {
                ChiakiLogo(size: 150)
                    .frame(maxWidth: .infinity)
                tiles
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 28) {
                ChiakiLogo(size: 120)
                tiles
            }
        }
    }

    private var tiles: some View {
        VStack(spacing: 14) {
            WelcomeView(
                hasProfiles: !store.profiles.isEmpty,
                focusedAction: $focusedAction,
                send: send
            )
            if let failure = store.accounts.operation.failure {
                CopyableErrorMessage(message: AccountsFailureMessage.text(for: failure), font: .callout)
                if failure == .loadFailed {
                    Button {
                        send(.reloadAccounts)
                    } label: {
                        Text(.mobileEntryReloadAccounts)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var back: (() -> Void)? {
        if let signIn = store.scope(state: \.route.signIn, action: \.route.signIn) {
            return {
                signIn.send(.view(.back))
            }
        }
        if let entry = store.scope(state: \.route.accountIDEntry, action: \.route.accountIDEntry) {
            return {
                entry.send(.view(.back))
            }
        }
        return nil
    }

    private var railAlignment: Alignment {
        switch railEdge {
        case .left:
            .leading
        case .right:
            .trailing
        case .top:
            .top
        case .bottom:
            .bottom
        }
    }

    private var railOffset: CGFloat {
        max(16, layout.sideInset + 4)
    }

    private var railInsets: EdgeInsets {
        switch railEdge {
        case .left:
            EdgeInsets(top: 0, leading: railOffset, bottom: 0, trailing: 0)
        case .right:
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: railOffset)
        case .top:
            EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)
        case .bottom:
            EdgeInsets(top: 0, leading: 0, bottom: max(10, layout.bottomInset), trailing: 0)
        }
    }

    private var insets: EdgeInsets {
        let side = max(24, layout.sideInset + 16)
        let beside = railOffset + MobileRail.thickness + 28
        var insets = EdgeInsets(top: 16, leading: side, bottom: 16, trailing: side)
        switch railEdge {
        case .left:
            insets.leading = max(side, beside)
        case .right:
            insets.trailing = max(side, beside)
        case .top:
            insets.top = 10 + MobileRail.thickness + 12
        case .bottom:
            insets.bottom = max(10, layout.bottomInset) + MobileRail.thickness + 12
        }
        return insets
    }
}

/// The floating rail while no account is signed in, holding Back.
struct MobileEntryRail: View {
    /// The window edge the rail lies along.
    let edge: LibraryRailEdge

    /// Goes back.
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .frame(width: MobileRail.stopSize, height: MobileRail.stopSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonBack))
        .padding(6)
        .glassEffect(AppGlass.control.interactive(), in: .capsule)
    }
}

/// PSN sign-in on a touch screen: the steps beside the code, or the web sign-in, with the unofficial-client
/// notice as a sheet until it is acknowledged.
struct MobileSignInView: View {
    /// The sign-in feature.
    let store: StoreOf<SignInFeature>

    /// The sign-in screen's focus, which the notice's checkbox shares.
    let focusedInput: MenuFocusState<EntryFocus?>.Binding

    @Environment(\.openURL) private var openURL
    @Environment(\.screenLayout) private var layout

    var body: some View {
        Group {
            switch store.method {
            case .qrCode:
                qrCode
            case .browser:
                browser
            }
        }
        .onAppear {
            store.send(.view(.appeared))
        }
        .sheet(isPresented: noticeShown) {
            UnofficialClientNotice {
                UnofficialClientAcknowledgement(acknowledged: store.acknowledged,
                                                focusedInput: focusedInput) {
                    store.send(.view(.acknowledge))
                }
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationBackground(.thinMaterial)
        }
    }

    private var noticeShown: Binding<Bool> {
        Binding(
            get: {
                !store.acknowledged
            },
            set: { shown in
                if !shown, !store.acknowledged {
                    store.send(.view(.back))
                }
            }
        )
    }

    @ViewBuilder private var qrCode: some View {
        if layout.sideBySide {
            HStack(spacing: 40) {
                steps
                    .frame(maxWidth: .infinity, alignment: .leading)
                code
            }
        } else {
            VStack(spacing: 28) {
                code
                steps
            }
        }
    }

    private var codeSide: CGFloat {
        240
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(.mobileSignInScanTitle)
                .font(.title.bold())
            Label(.mobileSignInScanStep, systemImage: "camera.viewfinder")
            Label(.mobileSignInTapStep, systemImage: "hand.tap")
            if case .failed(let failure) = store.phase {
                Text(AccountsFailureMessage.text(for: failure))
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text(.mobileSignInCodeRotates)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if case .failed = store.phase {
                    Button {
                        store.send(.view(.start))
                    } label: {
                        Label(.mobileSignInNewCode, systemImage: "qrcode")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
                    .foregroundStyle(.black)
                }
                if store.offersQRCode {
                    Button {
                        store.send(.view(.choose(.browser)))
                    } label: {
                        Label(.mobileSignInUseBrowser, systemImage: "safari")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .labelStyle(MobileStepLabelStyle())
    }

    @ViewBuilder private var code: some View {
        if let code = store.code {
            Button {
                if let destination = URL(string: code.approvalURL) {
                    openURL(destination)
                }
            } label: {
                QRCodeImage(code.approvalURL, side: codeSide, label: .mobileSignInCodeLabel)
            }
            .buttonStyle(.plain)
            .disabled(!store.acknowledged)
            .accessibilityHint(Text(.mobileSignInCodeHint))
        } else {
            ProgressView {
                Text(.mobileSignInPreparingCode)
            }
            .frame(width: codeSide, height: codeSide)
        }
    }

    @ViewBuilder private var browser: some View {
        if layout.sideBySide {
            HStack(spacing: 40) {
                ChiakiLogo(size: 150)
                    .frame(maxWidth: .infinity)
                browserForm
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 28) {
                ChiakiLogo(size: 120)
                browserForm
            }
        }
    }

    private var browserForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(.mobileSignInEmailTitle)
                    .font(.title.bold())
                Text(.mobileSignInEmailDetail)
                    .foregroundStyle(.secondary)
            }
            if case .failed(let failure) = store.phase {
                Text(AccountsFailureMessage.text(for: failure))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Button {
                store.send(.view(.start))
            } label: {
                Text(.mobileSignInSignIn)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(!store.acknowledged)
            if store.offersQRCode {
                Button {
                    store.send(.view(.choose(.qrCode)))
                } label: {
                    Label(.mobileSignInUseQRCode, systemImage: "qrcode")
                }
                .buttonStyle(.glass)
            }
            Text(.mobileSignInPasskeyNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A sign-in step: its symbol in the accent colour beside its text.
struct MobileStepLabelStyle: LabelStyle {
    /// Lays out one step.
    ///
    /// - Parameter configuration: The label's title and icon.
    /// - Returns: The step.
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon
                .foregroundStyle(Palette.accent)
            configuration.title
        }
        .font(.body)
    }
}

/// The Base64 PSN ID profile on a touch screen, laid out like Welcome: the animated logo beside the title, the
/// name and account id rows and Create Profile, on one screen.
struct MobileAccountIDView: View {
    /// The entry feature whose name and account id the rows edit.
    @Bindable var store: StoreOf<AccountIDEntryFeature>

    /// Why the last save failed, if it did.
    let failure: AccountsFailure?

    @Environment(\.screenLayout) private var layout

    var body: some View {
        if layout.sideBySide {
            HStack(spacing: 40) {
                ChiakiLogo(size: 150)
                    .frame(maxWidth: .infinity)
                form
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 28) {
                ChiakiLogo(size: 120)
                form
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(.mobileAccountIDTitle)
                    .font(.title.bold())
                Text(.mobileAccountIDDetail)
                    .foregroundStyle(.secondary)
            }
            MobileSettingsGroup(footer: failure.map(AccountsFailureMessage.text(for:))) {
                MobileTextEntryRow(
                    title: .mobileAccountIDName,
                    prompt: .mobileAccountIDNamePrompt,
                    text: $store.name
                )
                MobileTextEntryRow(
                    title: .mobileAccountIDAccountID,
                    prompt: .mobileAccountIDAccountIDPrompt,
                    text: $store.accountID,
                    invalid: !store.accountID.isEmpty && store.validAccountID == nil
                )
            }
            Button {
                store.send(.view(.submit))
            } label: {
                Text(.mobileAccountIDCreate)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(store.validAccountID == nil)
        }
    }
}
