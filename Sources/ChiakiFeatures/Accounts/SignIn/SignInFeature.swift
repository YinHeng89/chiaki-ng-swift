import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Signs a PlayStation account in, by a QR code another device approves or through the web sign-in page, and saves
/// it.
///
/// A new account starts with a QR code as soon as the screen appears, and the person can switch to the web sign-in
/// page instead; signing an account in again uses the web page only. A QR attempt runs
/// `ChiakiClients/AccountsClient/signInWithQR` and shows each code it reports. A web attempt captures the
/// NPSSO with `ChiakiClients/AccountsClient/captureSignIn` and hands it, without copying, to
/// `ChiakiClients/AccountsClient/signIn`. Every report and the result carry the attempt's
/// `ChiakiModels/OperationID`; a cancelled attempt cannot move the screen.
@Reducer
public struct SignInFeature {
    /// The sign-in screen's state.
    @ObservableState
    public struct State: Equatable {
        /// How the account signs in.
        public enum Method: Hashable, Sendable {
            /// By a QR code another device scans and approves.
            case qrCode

            /// Through the web sign-in page in the app.
            case browser
        }

        /// Where the sign-in is.
        public enum Phase: Hashable, Sendable {
            /// Waiting for the user to start.
            case idle

            /// A QR code is being obtained, at the start or after the shown code expired.
            case preparingCode(OperationID)

            /// A QR code is shown for another device to approve.
            case showingCode(OperationID, QRSignInCode)

            /// The page is being opened.
            case opening(OperationID)

            /// The sign-in page is shown.
            case browsing(OperationID, SignInPage)

            /// The user signed in and the NPSSO is being read from the page.
            case completing(OperationID, SignInPage)

            /// The core is signing in, after the NPSSO was captured or the QR code approved, and saving the
            /// account.
            case signingIn(OperationID)

            /// The last attempt failed.
            case failed(SignInFailure)

            /// The running attempt, if one runs.
            public var attempt: OperationID? {
                switch self {
                case .preparingCode(let id), .showingCode(let id, _), .opening(let id), .browsing(let id, _),
                     .completing(let id, _), .signingIn(let id):
                    id
                case .idle, .failed:
                    nil
                }
            }
        }

        /// The account being signed in again, or `nil` for a new account.
        public let reconnecting: UUID?

        /// How the account signs in.
        public internal(set) var method: Method

        /// Where the sign-in is.
        public internal(set) var phase = Phase.idle

        /// Whether the person has acknowledged that the app is an unofficial client, which signing in needs.
        public internal(set) var acknowledged = false

        /// The certificate the shown page's connection was secured with, once a page has finished loading.
        public internal(set) var certificate: SignInCertificate?

        /// Whether the account may sign in on the web sign-in page; a phone signs in by QR code only.
        public let offersBrowser: Bool

        /// Opens the screen on a QR code, for a new account and for one signing in again alike.
        ///
        /// - Parameters:
        ///   - reconnecting: The account to sign in again, or `nil` for a new account.
        ///   - offersBrowser: Whether the account may sign in on the web sign-in page.
        public init(reconnecting: UUID? = nil, offersBrowser: Bool = true) {
            self.reconnecting = reconnecting
            self.offersBrowser = offersBrowser
            method = .qrCode
        }

        /// Whether the person may switch between a QR code and the web sign-in page.
        public var offersQRCode: Bool {
            offersBrowser
        }

        /// The QR code to show, while one waits for approval.
        public var code: QRSignInCode? {
            if case .showingCode(_, let code) = phase {
                return code
            }
            return nil
        }

        /// The page to show, while the sign-in page is up or being read.
        public var page: SignInPage? {
            switch phase {
            case .browsing(_, let page), .completing(_, let page):
                page
            case .idle, .preparingCode, .showingCode, .opening, .signingIn, .failed:
                nil
            }
        }

        /// Whether the NPSSO is being read from the page.
        public var isCompleting: Bool {
            if case .completing = phase {
                return true
            }
            return false
        }

        /// Whether an attempt runs.
        public var isRunning: Bool {
            phase.attempt != nil
        }

        /// Whether the attempt has left this screen for the sign-in page or the account being saved, so the screen
        /// gives way to the progress the sign-in shows; a QR code being prepared or shown stays on the screen.
        public var isBusy: Bool {
            switch phase {
            case .opening, .browsing, .completing, .signingIn:
                true
            case .idle, .preparingCode, .showingCode, .failed:
                false
            }
        }
    }

    /// Everything the sign-in screen reacts to.
    public enum Action: Equatable {
        /// Something the user did.
        case view(View)

        /// The browser reported a stage of an attempt.
        case stageReported(OperationID, SignInStage)

        /// A QR attempt reported a step.
        case codeReported(OperationID, QRSignInProgress)

        /// The NPSSO of an attempt was captured and is being signed in.
        case captured(OperationID)

        /// An attempt ended.
        case finished(OperationID, Result<AccountProfile, SignInFailure>)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// The screen appeared; a QR sign-in shows its first code.
            case appeared

            /// Starts the chosen method again: opens the sign-in page or shows a new QR code.
            case start

            /// Ticks or clears the acknowledgement that the app is an unofficial client.
            case acknowledge

            /// Switches to another way of signing in, abandoning a running attempt.
            case choose(State.Method)

            /// Closes the sign-in page and stays on the screen.
            case closePage

            /// Leaves the screen, abandoning a running attempt.
            case back
        }

        /// What the sign-in reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The user started signing in.
            case started

            /// The account was signed in and saved.
            case signedIn(AccountProfile)

            /// The user left without signing in.
            case left
        }
    }

    private enum CancelID {
        case attempt
    }

    @Dependency(\.accounts) private var accounts
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard state.method == .qrCode, state.phase == .idle else {
                    return .none
                }
                return .merge(.send(.delegate(.started)), start(&state))
            case .view(.start):
                return .merge(.send(.delegate(.started)), start(&state))
            case .view(.acknowledge):
                state.acknowledged.toggle()
                return .none
            case .view(.choose(let method)):
                guard method != state.method, state.offersQRCode else {
                    return .none
                }
                let running = state.isRunning
                state.method = method
                state.phase = .idle
                state.certificate = nil
                let started: Effect<Action> = method == .qrCode
                    ? .merge(.send(.delegate(.started)), start(&state))
                    : .none
                return .concatenate(
                    running
                        ? .cancel(id: CancelID.attempt)
                        : .none,
                    started
                )
            case .view(.closePage):
                guard state.isRunning else {
                    return .none
                }
                state.phase = .idle
                state.certificate = nil
                return .cancel(id: CancelID.attempt)
            case .view(.back):
                let running = state.isRunning
                state.phase = .idle
                state.certificate = nil
                return .concatenate(
                    running
                        ? .cancel(id: CancelID.attempt)
                        : .none,
                    .send(.delegate(.left))
                )
            case let .stageReported(id, stage):
                guard state.phase.attempt == id else {
                    return .none
                }
                switch (state.phase, stage) {
                case (.opening, .browsing(let page)), (.browsing, .browsing(let page)):
                    state.phase = .browsing(id, page)
                    state.certificate = nil
                case (.browsing(_, let page), .secured(let secured, let certificate)) where page == secured:
                    state.certificate = certificate
                case (.browsing(_, let page), .completing):
                    state.phase = .completing(id, page)
                default:
                    break
                }
                return .none
            case let .codeReported(id, progress):
                guard state.phase.attempt == id else {
                    return .none
                }
                switch (state.phase, progress) {
                case (.preparingCode, .preparing), (.showingCode, .preparing):
                    state.phase = .preparingCode(id)
                case (.preparingCode, .awaitingApproval(let code)), (
                    .showingCode,
                    .awaitingApproval(let code)
                ):
                    state.phase = .showingCode(id, code)
                case (.preparingCode, .signingIn), (.showingCode, .signingIn):
                    state.phase = .signingIn(id)
                default:
                    break
                }
                return .none
            case .captured(let id):
                guard state.phase.attempt == id else {
                    return .none
                }
                state.phase = .signingIn(id)
                return .none
            case let .finished(id, result):
                guard state.phase.attempt == id else {
                    return .none
                }
                state.certificate = nil
                switch result {
                case .success(let profile):
                    state.phase = .idle
                    return .send(.delegate(.signedIn(profile)))
                case .failure(let failure):
                    state.phase = .failed(failure)
                    return .none
                }
            case .delegate:
                return .none
            }
        }
    }

    private func start(_ state: inout State) -> Effect<Action> {
        guard !state.isRunning else {
            return .none
        }
        let id = OperationID(uuid: uuid())
        let profile = state.reconnecting ?? uuid()
        switch state.method {
        case .qrCode:
            state.phase = .preparingCode(id)
            return showCodes(id, profile: profile)
        case .browser:
            state.phase = .opening(id)
            return openPage(id, profile: profile)
        }
    }

    private func showCodes(_ id: OperationID, profile: UUID) -> Effect<Action> {
        .run { [accounts] send in
            let (steps, feed) = AsyncStream.makeStream(of: QRSignInProgress.self)
            let forwarding = Task {
                for await step in steps {
                    await send(.codeReported(id, step))
                }
            }
            let result = await accounts.signInWithQR(profile) { step in
                feed.yield(step)
            }
            feed.finish()
            await forwarding.value
            await send(.finished(id, result))
        }
        .cancellable(id: CancelID.attempt, cancelInFlight: true)
    }

    private func openPage(_ id: OperationID, profile: UUID) -> Effect<Action> {
        return .run { [accounts] send in
            let (stages, feed) = AsyncStream.makeStream(of: SignInStage.self)
            let forwarding = Task {
                for await stage in stages {
                    await send(.stageReported(id, stage))
                }
            }
            let result: Result<AccountProfile, SignInFailure>
            do throws(SignInFailure) {
                let capture = try await accounts.captureSignIn { stage in
                    feed.yield(stage)
                }
                feed.finish()
                await forwarding.value
                await send(.captured(id))
                result = await accounts.signIn(profile, capture)
            } catch {
                result = .failure(error)
            }
            feed.finish()
            await forwarding.value
            await send(.finished(id, result))
        }
        .cancellable(id: CancelID.attempt, cancelInFlight: true)
    }
}
