import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The screens before the library: launching, welcome, sign-in, account id entry, adding a console and
/// pairing, under the shared logo with one controller focus graph.
///
/// The screen shown follows ``RootFeature/State/route``; ``EntryFocusGraph`` decides where focus starts and
/// how Up and Down move between the screen's controls.
struct EntryScreen: View {
    /// The root.
    let store: StoreOf<RootFeature>

    /// The height of the window, which the root still passes; the scroll view centres its column against its
    /// own container instead.
    let height: CGFloat

    @Environment(\.menuNavigator) private var navigator
    @Environment(\.screenLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @MenuFocusState private var focusedInput: EntryFocus?
    @MenuFocusState private var focusedAction: String?
    @MenuFocusState private var consoleKindFocus: RegistrationFlow.ConsoleKind?
    @State private var hostWindow: PlatformWindow?

    /// The touch welcome and sign-in on a touch screen, the scrolling column everywhere else.
    var body: some View {
        if layout.touch, navigator?.inputMode.mode != .controller {
            if touchScreen {
                MobileEntryView(store: store, send: send)
            } else {
                column
            }
        } else {
            column
        }
    }

    private var touchScreen: Bool {
        switch screen {
        case .welcome, .signIn, .accountID:
            true
        default:
            false
        }
    }

    private var column: some View {
        ScrollView {
            ZStack {
                Color.clear
                    .containerRelativeFrame(.vertical)
                stack
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(EntryScrollMargins(touch: layout.touch))
        .padding(
            .vertical,
            layout.isShort
                ? 18
                : 64
        )
        .onChange(of: screen, initial: true) { _, screen in
            focusPreferred(on: screen)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
            guard let window = notification.object as? PlatformWindow, window === hostWindow,
                  EntryFocusGraph.preferred(on: screen, conditions) != nil, stops != nil else {
                return
            }
            focusPreferred(on: screen)
        }
        .background(WindowAccessor { hostWindow = $0 })
        .menuHandlers(move: { window, direction in
            guard window === WindowFocus.keyWindow,
                  window === hostWindow,
                  !(navigator?.inputGate.isBlocking ?? false),
                  !(navigator?.isTrackingMenu ?? false) else {
                return false
            }
            return move(direction)
        })
    }

    private var stack: some View {
        VStack(spacing: 0) {
            if presentation.usesSharedLogo {
                ChiakiLogo(
                    size: layout.isShort
                        ? 64
                        : 120,
                    isConnecting: presentation.accountWorkInProgress
                )
                .frame(
                    height: layout.isShort
                        ? 92
                        : 170
                )
            }
            content
                .id(screen)
                .transition(AppMotion.transition(reduced: reduceMotion))
                .frame(
                    minHeight: presentation.usesSharedLogo && !layout.isShort
                        ? 260
                        : nil
                )
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: screen)
        .frame(maxWidth: 720)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .launching:
            Color.clear
        case .loading:
            ProgressView(.appEntryOpeningAccounts).padding(.vertical, 24)
        case .saving:
            AccountSavingView(focusedAction: $focusedAction) {
                send(.cancelAccountWork)
            }
        case .welcome, .signIn, .accountID, .addConsoleByAddress, .addConsole, .pairing:
            VStack(spacing: 18) {
                EntryRouteContent(
                    store: store,
                    focusedInput: $focusedInput,
                    focusedAction: $focusedAction,
                    consoleKindFocus: $consoleKindFocus,
                    send: send
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 40)
                .environment(\.menuMove, menuMove)
                if let failure = store.accounts.operation.failure, presentation.showsAccountsFailure {
                    CopyableErrorMessage(message: AccountsFailureMessage.text(for: failure), font: .callout)
                    if store.route == .welcome, failure == .loadFailed {
                        FlowSecondaryButton(
                            label: .appEntryReloadAccounts,
                            focus: "Reload accounts",
                            focusedAction: $focusedAction
                        ) {
                            send(.reloadAccounts)
                        }
                        .environment(\.menuMove, menuMove)
                    }
                }
            }
        }
    }

    private var presentation: EntryPresentation {
        EntryPresentation(state: store.state)
    }

    private var screen: EntryFocusGraph.Screen {
        presentation.screen
    }

    private var stops: [EntryFocusGraph.Stop]? {
        presentation.stops
    }

    private var conditions: EntryFocusGraph.Conditions {
        presentation.conditions
    }

    private var menuMove: (@MainActor (MenuMoveDirection) -> Void)? {
        guard stops != nil else {
            return nil
        }
        return { direction in
            _ = move(direction)
        }
    }

    private func send(_ action: RootFeature.Action.View) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        if focusedInput != nil {
            withTransaction(transaction) {
                focusedInput = nil
                navigator?.endEditing()
            }
        }
        _ = withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            store.send(.view(action))
        }
    }

    private var currentStop: EntryFocusGraph.Stop? {
        if let focusedInput {
            return .input(focusedInput)
        }
        if let focusedAction {
            return .action(focusedAction)
        }
        if consoleKindFocus != nil {
            return .consoleKind
        }
        return nil
    }

    private func move(_ direction: MenuMoveDirection) -> Bool {
        guard let stops, !stops.isEmpty else {
            return false
        }
        guard let current = currentStop, let index = stops.firstIndex(of: current) else {
            guard direction == .down else {
                return false
            }
            focus(stops[0])
            return true
        }
        let direction = EntryFocusGraph.tiled(screen)
            ? direction.alongRow
            : direction
        guard direction == .up || direction == .down else {
            return current != .consoleKind
        }
        let next = direction == .down
            ? index + 1
            : index - 1
        guard stops.indices.contains(next) else {
            if direction == .up {
                NotificationCenter.default.post(name: .focusSettingsControl, object: WindowFocus.keyWindow)
            }
            return true
        }
        focus(stops[next])
        return true
    }

    private func focus(_ stop: EntryFocusGraph.Stop) {
        switch stop {
        case .action(let action):
            focusedInput = nil
            consoleKindFocus = nil
            focusedAction = action
        case .input(let input):
            focusedAction = nil
            consoleKindFocus = nil
            focusedInput = input
        case .consoleKind:
            focusedAction = nil
            focusedInput = nil
            consoleKindFocus = store.scope(state: \.route.addConsole, action: \.route.addConsole)?
                .kind ?? .ps5
        }
    }

    private func focusPreferred(on target: EntryFocusGraph.Screen) {
        guard let stop = EntryFocusGraph.preferred(on: target, conditions) else {
            focusedAction = nil
            return
        }
        Task { @MainActor in
            for attempt in 0..<20 {
                await Task.yield()
                guard screen == target else {
                    return
                }
                if attempt == 0 {
                    focus(stop)
                } else if focusedAction == nil, focusedInput == nil, consoleKindFocus == nil {
                    if let window = WindowFocus.keyWindow {
                        navigator?.resignFocus(in: window)
                    }
                    focus(stop)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

/// The scroll margins of the entry screen: the app's indicator margins on a pointer, and none on touch, where
/// the trailing margin would push the centred column off centre.
private struct EntryScrollMargins: ViewModifier {
    /// Whether touch is the primary way to point.
    let touch: Bool

    /// The scroll view with the margins that suit the pointer.
    ///
    /// - Parameter content: The entry screen's scroll view.
    /// - Returns: The scroll view, with the app's margins unless touch is used.
    @ViewBuilder func body(content: Content) -> some View {
        if touch {
            content
        } else {
            content.appVerticalScrollStyle()
        }
    }
}

/// The screen of the root's route before the library: welcome, sign-in, account id entry, adding a console or
/// pairing, wired to the entry screen's shared focus.
private struct EntryRouteContent: View {
    /// The root.
    let store: StoreOf<RootFeature>

    /// The focus of the screen's text fields.
    let focusedInput: MenuFocusState<EntryFocus?>.Binding

    /// The focus of the screen's buttons, by title.
    let focusedAction: MenuFocusState<String?>.Binding

    /// The focus of the console kind picker.
    let consoleKindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding

    /// Sends what the person did to the root.
    let send: (RootFeature.Action.View) -> Void

    @Environment(\.streamerMode) private var streamerMode

    /// The route's screen.
    var body: some View {
        switch store.route {
        case .welcome:
            WelcomeView(hasProfiles: !store.profiles.isEmpty, focusedAction: focusedAction, send: send)
        case .signIn:
            if let signIn = store.scope(state: \.route.signIn, action: \.route.signIn) {
                SignInView(store: signIn, focusedInput: focusedInput)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .accountIDEntry:
            if let entry = store.scope(state: \.route.accountIDEntry, action: \.route.accountIDEntry) {
                AccountIDEntryView(
                    store: entry,
                    failure: store.accounts.operation.failure,
                    focusedInput: focusedInput
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        case .addConsole:
            if let addConsole = store.scope(state: \.route.addConsole, action: \.route.addConsole) {
                if EntryPresentation(state: store.state).addsConsoleByAddress {
                    AddConsoleByAddressView(
                        store: addConsole,
                        failure: store.pairingFailure,
                        focusedInput: focusedInput,
                        focusedAction: focusedAction,
                        kindFocus: consoleKindFocus
                    )
                } else {
                    AddConsoleView(
                        store: addConsole,
                        discovery: store.discovery,
                        failure: store.pairingFailure.map(PairingFailureMessage.text(for:))
                            ?? store.registrationFailure.map(RegistrationFailureMessage.text(for:))
                    )
                }
            }
        case .pairing:
            if let pairing = store.scope(state: \.route.pairing, action: \.route.pairing) {
                PairingView(
                    store: pairing,
                    focusedInput: focusedInput,
                    focusedAction: focusedAction,
                    streamerMode: streamerMode
                )
            }
        case .launching, .library, .stream, .kakusanGuest:
            EmptyView()
        }
    }
}

/// What the screens before the library show for the root's state: the screen, whether it sits under the
/// shared logo, whether account work runs, and the conditions its focus graph depends on.
@MainActor
private struct EntryPresentation {
    /// The root's state.
    let state: RootFeature.State

    /// The screen shown.
    var screen: EntryFocusGraph.Screen {
        if state.route == .launching {
            return .launching
        }
        if accountWorkInProgress {
            if case .loading = state.accounts.operation {
                return .loading
            }
            return .saving
        }
        switch state.route {
        case .signIn:
            return .signIn(state.route.signIn
                .map(EntryFocusGraph.SignInLayout.init) ?? .browser(offersQRCode: false))
        case .accountIDEntry:
            return .accountID
        case .addConsole:
            return addsConsoleByAddress
                ? .addConsoleByAddress
                : .addConsole
        case .pairing:
            guard let pairing = state.route.pairing else {
                return .pairing(nil)
            }
            return .pairing(PairingView.screen(of: pairing.flow))
        case .launching, .welcome, .library, .stream, .kakusanGuest:
            return .welcome
        }
    }

    /// Whether the screen sits under the shared logo.
    var usesSharedLogo: Bool {
        switch screen {
        case .loading, .saving, .welcome, .signIn, .accountID:
            true
        case .launching, .addConsoleByAddress, .addConsole, .pairing:
            false
        }
    }

    /// Whether a failed account operation is shown below the screen.
    var showsAccountsFailure: Bool {
        switch state.route {
        case .signIn, .accountIDEntry:
            false
        case .launching, .welcome, .library, .addConsole, .pairing, .stream, .kakusanGuest:
            true
        }
    }

    /// Whether a console is added by its address, for an account that did not sign in to PlayStation Network.
    var addsConsoleByAddress: Bool {
        state.selectedProfile?.kind != .npsso
    }

    /// Whether accounts load, save or sign in.
    var accountWorkInProgress: Bool {
        switch state.accounts.operation {
        case .loading, .saving:
            true
        case .idle, .confirmingDeletion, .deleting, .failed:
            state.route.signIn?.isBusy == true
        }
    }

    /// What the focus graph needs to know about the screen's controls.
    var conditions: EntryFocusGraph.Conditions {
        EntryFocusGraph.Conditions(
            hasProfiles: !state.profiles.isEmpty,
            accountsLoadFailed: state.accounts.operation.failure == .loadFailed,
            validConsoleAddress: state.route.addConsole?.validAddress != nil,
            validAccountID: state.route.accountIDEntry?.validAccountID != nil,
            canSubmitPIN: state.route.pairing?.canSubmitPIN == true,
            signInAcknowledged: state.route.signIn?.acknowledged == true
        )
    }

    /// The screen's focus stops from top to bottom, or `nil` when the screen keeps its own focus.
    var stops: [EntryFocusGraph.Stop]? {
        EntryFocusGraph.stops(on: screen, conditions)
    }
}

/// The controller focus order of the entry screens: which control starts focused, and the vertical order of
/// the controls Up and Down walk through.
enum EntryFocusGraph {
    /// One control focus can rest on.
    enum Stop: Hashable {
        /// A button identified by its label.
        case action(String)

        /// A text field or button of an entry form.
        case input(EntryFocus)

        /// The console generation switch.
        case consoleKind
    }

    /// An entry screen as focus sees it.
    enum Screen: Hashable {
        /// The saved accounts are being read at launch.
        case launching

        /// The accounts are read again.
        case loading

        /// An account is being saved or signed in.
        case saving

        /// The welcome screen.
        case welcome

        /// The PlayStation sign-in screen, as it is laid out.
        case signIn(SignInLayout)

        /// The account id screen.
        case accountID

        /// The add-console screen of an account added by account id.
        case addConsoleByAddress

        /// The add-console screen of a signed-in account, which moves its own focus.
        case addConsole

        /// The pairing screen.
        case pairing(PairingView.Screen?)
    }

    /// What the PlayStation sign-in screen shows, as focus sees it.
    enum SignInLayout: Hashable {
        /// The web sign-in page is offered, with a switch to a QR code when the account is new.
        case browser(offersQRCode: Bool)

        /// A QR code is being prepared or shown.
        case qrCode

        /// The QR sign-in failed and offers a new code.
        case qrFailed

        /// The layout of a sign-in.
        ///
        /// - Parameter signIn: The sign-in's state.
        init(_ signIn: SignInFeature.State) {
            switch (signIn.method, signIn.phase) {
            case (.browser, _):
                self = .browser(offersQRCode: signIn.offersQRCode)
            case (.qrCode, .failed):
                self = .qrFailed
            case (.qrCode, _):
                self = .qrCode
            }
        }
    }

    /// What the screens show that changes their focus order.
    struct Conditions: Equatable {
        /// Whether an account exists, so the welcome screen offers to return to the library.
        var hasProfiles = false

        /// Whether the accounts could not be read, so the welcome screen offers to read them again.
        var accountsLoadFailed = false

        /// Whether the typed console address is valid, so Continue is shown.
        var validConsoleAddress = false

        /// Whether the typed account id is valid, so the save button is shown.
        var validAccountID = false

        /// Whether the typed PIN can be submitted, so the pair button is shown.
        var canSubmitPIN = false

        /// Whether the unofficial-client notice is acknowledged, so the sign-in's main button is offered and
        /// focus starts on the sign-in rather than on the acknowledgement.
        var signInAcknowledged = false
    }

    /// Where focus starts on a screen.
    ///
    /// - Parameters:
    ///   - screen: The screen.
    ///   - conditions: What the screen shows.
    /// - Returns: The first control, or `nil` when the screen moves its own focus.
    static func preferred(on screen: Screen, _ conditions: Conditions) -> Stop? {
        switch screen {
        case .launching, .loading, .addConsole, .pairing(nil):
            nil
        case .saving, .pairing(.attempting):
            .action("Cancel")
        case .accountID:
            .input(.accountName)
        case .signIn where !conditions.signInAcknowledged:
            .input(.acknowledgeUnofficial)
        case .signIn(.browser):
            .input(.signInWithPlayStation)
        case .signIn(.qrCode):
            .input(.signInOtherMethod)
        case .signIn(.qrFailed):
            .input(.newSignInCode)
        case .addConsoleByAddress:
            .input(.consoleAddress)
        case .pairing(.enteringPIN):
            .input(.pin)
        case .welcome:
            .action("PSN account")
        }
    }

    /// Whether a screen lays its choices out on a ``FlowTileRow``, so Left and Right walk them as well as Up
    /// and Down.
    ///
    /// - Parameter screen: The screen.
    /// - Returns: `true` on the welcome screen and every sign-in screen.
    static func tiled(_ screen: Screen) -> Bool {
        switch screen {
        case .welcome, .signIn, .accountID:
            true
        default:
            false
        }
    }

    /// The controls Up and Down walk through on a screen, top to bottom.
    ///
    /// - Parameters:
    ///   - screen: The screen.
    ///   - conditions: What the screen shows.
    /// - Returns: The controls, or `nil` when the screen moves its own focus.
    static func stops(on screen: Screen, _ conditions: Conditions) -> [Stop]? {
        switch screen {
        case .launching, .loading, .addConsole, .pairing(nil):
            return nil
        case .saving, .pairing(.attempting):
            return [.action("Cancel")]
        case .pairing(.enteringPIN):
            return [.input(.pin)]
                + (conditions.canSubmitPIN
                    ? [.input(.pairConsole)]
                    : [])
                    + [.action("Back")]
        case .addConsoleByAddress:
            return [.input(.consoleAddress), .consoleKind]
                + (conditions.validConsoleAddress
                    ? [.input(.consoleContinue)]
                    : [])
                    + [.action("Back")]
        case .welcome:
            return [.action("PSN account"), .action("Base64 PSN ID profile")]
                + (KakusanBuild.included
                    ? [.action("Join a game")]
                    : [])
                    + (conditions.hasProfiles
                        ? [.action("Back to profiles")]
                        : [])
                        + (conditions.accountsLoadFailed
                            ? [.action("Reload accounts")]
                            : [])
        case .signIn(.browser(let offersQRCode)):
            return [.input(.acknowledgeUnofficial)]
                + (conditions.signInAcknowledged
                    ? [.input(.signInWithPlayStation)]
                    : [])
                    + (offersQRCode
                        ? [.input(.signInOtherMethod)]
                        : [])
                        + [.input(.signInBack)]
        case .signIn(.qrCode):
            return [.input(.acknowledgeUnofficial), .input(.signInOtherMethod), .input(.signInBack)]
        case .signIn(.qrFailed):
            return [
                .input(.acknowledgeUnofficial), .input(.newSignInCode), .input(.signInOtherMethod),
                .input(.signInBack)
            ]
        case .accountID:
            return [.input(.accountName), .input(.accountID)]
                + (conditions.validAccountID
                    ? [.input(.createProfile)]
                    : [])
                    + [.input(.accountIDBack)]
        }
    }
}

extension MenuMoveDirection {
    /// The direction read along a row of tiles: Left as Up and Right as Down, so a row shares the vertical stop
    /// order.
    fileprivate var alongRow: MenuMoveDirection {
        switch self {
        case .left:
            .up
        case .right:
            .down
        default:
            self
        }
    }
}
