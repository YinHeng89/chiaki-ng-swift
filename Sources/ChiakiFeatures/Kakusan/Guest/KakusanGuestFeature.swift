import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Joins someone else's shared session: the pasted invitation, the reply, code checks, the stream and leaving.
///
/// The join is the `ChiakiModels/KakusanGuestJoin` machine; every answer carries the id of the session or
/// operation that asked. The feature owns the card's drafts, its controls and their selection, and the leave
/// prompt. The controls come from `ChiakiModels/KakusanGuestControls`, the one list the card renders and
/// controller navigation moves through.
@Reducer
public struct KakusanGuestFeature {
    /// How long the stream may run before its first frame.
    static let firstFrameDeadline = Duration.seconds(30)

    /// The guest's state.
    @ObservableState
    public struct State: Equatable {
        /// The join.
        public var join = KakusanGuestJoin()
        /// Identifies the join opened last, from the moment it opens until the next one opens, whatever its
        /// session does meanwhile.
        public internal(set) var joinID: UUID?
        /// What is known about the host.
        public var host = KakusanGuestHost.unknown
        /// How the proven host was recognised.
        public var recognition: KakusanRecognition?
        /// The host proven before the stream started, kept for remembering it later.
        public var verifiedHost: KakusanIdentity?
        /// The stream menu, while streaming.
        public var streamMenu: StreamMenuReducer.State?
        /// Naming the verified host's device.
        @Presents public var remember: KakusanRememberFeature.State?
        /// The invitation as typed or pasted.
        public var invitation = ""
        /// The host's code as typed.
        public var code = ""
        /// Whether the reply was copied since it was shown.
        public internal(set) var copied = false
        /// The reply as a file to share, once written.
        public internal(set) var shareFile: URL?
        /// The card's controls and the selected one.
        public internal(set) var controls = KakusanControlGrid()
        /// Whether leaving is being confirmed.
        public internal(set) var leavePrompt = KakusanLeavePrompt.hidden
        /// Counts requests to show the on-screen keyboard for the focused field.
        public internal(set) var keyboardRequest = 0
        /// The video view of the running guest stream.
        public var surface: StreamSurface?

        /// Creates an idle guest.
        public init() {}

        /// Whether the guest screen is shown.
        public var presented: Bool {
            join.presented
        }

        /// The host, once proven.
        public var hostPeer: KakusanIdentity? {
            if case .proven(let peer) = host {
                return peer
            }
            return nil
        }

        /// The host's name: claimed by the invitation, or remembered once proven.
        public var hostName: String? {
            switch host {
            case .unknown:
                nil
            case .claimed(let name):
                name
            case .proven:
                recognition?.name
            }
        }

        /// Whether the verified host's device can be remembered.
        public var canRemember: Bool {
            verifiedHost != nil && hostName == nil
        }

        /// Whether the shared stream shows video.
        public var playing: Bool {
            guard case .streaming(_, let stream) = join.phase else {
                return false
            }
            return KakusanGuestFeature.playing(stream.video)
        }

        /// Whether controller input drives the guest's stream menu rather than the shared game: while the
        /// stream shows video and its menu navigates.
        public var controllerNavigationActive: Bool {
            playing && (streamMenu?.navigation.isActive ?? false)
        }

        /// Shows the card's controls for the current phase, keeping the selection while it is still shown.
        mutating func followPhase() {
            let grid = KakusanGuestControls.grid(for: join.phase, canRemember: canRemember)
            controls.show(grid.rows, preferring: grid.selection)
        }

        /// Whether the disclosure is accepted.
        public var disclosureAccepted: Bool {
            if case .disclosureAccepted = join.phase {
                return true
            }
            return false
        }
    }

    /// Everything the guest reacts to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to the typed invitation or code.
        case binding(BindingAction<State>)
        /// Something the user did on the card.
        case view(View)
        /// Open the guest screen.
        case open
        /// Preview an invitation.
        case submitInvitation(String)
        /// A preview came back.
        case previewResult(UUID, KakusanBlock, Result<KakusanInvitationPreview, KakusanError>)
        /// The proven host was recognised.
        case recognised(KakusanPublicKey, KakusanRecognition)
        /// Accept or withdraw the disclosure.
        case setDisclosure(Bool)
        /// Start the session and create the reply.
        case createReply
        /// The session reported an event.
        case event(UUID, KakusanGuestEvent)
        /// The session failed.
        case playFailed(UUID, KakusanError)
        /// The session ended.
        case playEnded(UUID)
        /// Check the host's code.
        case submitCode(String)
        /// A code check came back.
        case codeResult(UUID, operation: UUID, KakusanCommandOutcome)
        /// The invitation expired.
        case expired(UUID)
        /// No frame came in time.
        case firstFrameTimedOut(UUID)
        /// Leave the session.
        case leave
        /// The session stopped.
        case stopped(UUID)
        /// Step back from the preview, or start over after an end.
        case back
        /// Name the verified host's device.
        case startRemembering
        /// The pasteboard's text arrived.
        case pasted(String?)
        /// The reply file was written.
        case shareFileReady(URL)
        /// The stream menu.
        case streamMenu(StreamMenuReducer.Action)
        /// The naming card.
        case remember(PresentationAction<KakusanRememberFeature.Action>)

        /// What the user did on the card.
        @CasePathable
        public enum View: Equatable, Sendable {
            /// A control was activated.
            case controlActivated(KakusanControl)
            /// Back was pressed.
            case backPressed
            /// Controller navigation moved the selection.
            case moved(KakusanGridStep)
            /// The invitation field was submitted.
            case invitationSubmitted
            /// The code field was submitted.
            case codeSubmitted
            /// The user confirmed leaving.
            case leaveConfirmed
            /// The user kept the session.
            case leaveDismissed
            /// The reply's share button appeared.
            case shareShown
        }
    }

    private enum CancelID: Hashable {
        case session, expiry, firstFrame, shareFile
    }

    @Dependency(\.kakusan) private var kakusan
    @Dependency(\.platform) private var platform
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date) private var date
    @Dependency(\.continuousClock) private var clock

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            let before = Self.stage(state.join.phase)
            let effect = reduce(&state, action)
            guard Self.stage(state.join.phase) != before else {
                return effect
            }
            state.code = ""
            state.copied = false
            state.shareFile = nil
            state.leavePrompt = .hidden
            return .merge(effect, .cancel(id: CancelID.shareFile))
        }
        .ifLet(\.streamMenu, action: \.streamMenu) {
            StreamMenuReducer()
        }
        .ifLet(\.$remember, action: \.remember) {
            KakusanRememberFeature()
        }
        Reduce { state, _ in
            state.followPhase()
            return .none
        }
    }

    /// Whether the guest stream's video has reached its first frame.
    static func playing(_ video: KakusanGuestVideo) -> Bool {
        if case .playing = video {
            return true
        }
        return false
    }

    private func reduce(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .binding:
            return .none
        case .view(let view):
            return handle(view, in: &state)
        case .open:
            return open(&state)
        case .submitInvitation(let text):
            return submitInvitation(text, in: &state)
        case let .previewResult(operation, block, result):
            return previewed(operation, block, result, in: &state)
        case let .recognised(key, recognition):
            return recognised(key, recognition, in: &state)
        case .setDisclosure(let accepted):
            return apply(.setDisclosure(accepted), in: &state)
        case .createReply:
            return createReply(in: &state)
        case let .event(session, event):
            return handle(event, in: session, state: &state)
        case let .playFailed(session, error):
            return apply(.session(session, .failed(error)), in: &state)
        case .playEnded(let session):
            return apply(.session(session, .ended), in: &state)
        case .submitCode(let text):
            return submitCode(text, in: &state)
        case let .codeResult(session, operation, outcome):
            return apply(.session(session, .codeResult(operation, outcome.error)), in: &state)
        case .expired(let session):
            return apply(.session(session, .expired), in: &state)
        case .firstFrameTimedOut(let session):
            return firstFrameTimedOut(session, in: &state)
        case .leave:
            return apply(.leave, in: &state)
        case .stopped(let session):
            return apply(.session(session, .stopped), in: &state)
        case .back:
            return apply(.back, in: &state)
        case .startRemembering:
            return startRemembering(&state)
        case .pasted(let text):
            state.invitation = text ?? state.invitation
            return submitTypedInvitation(&state)
        case .shareFileReady(let url):
            state.shareFile = url
            return .none
        case .remember(.presented(.delegate(.finished(let saved)))):
            return remembered(saved, in: &state)
        case .streamMenu(.delegate(.stopRequested)):
            return .send(.leave)
        case .remember, .streamMenu:
            return .none
        }
    }
}

extension KakusanGuestFeature {
    private func recognised(
        _ key: KakusanPublicKey,
        _ recognition: KakusanRecognition,
        in state: inout State
    ) -> Effect<Action> {
        guard state.hostPeer?.publicKey == key else {
            return .none
        }
        state.recognition = recognition
        return .none
    }

    private func firstFrameTimedOut(_ session: UUID, in state: inout State) -> Effect<Action> {
        guard case .streaming(session, let stream) = state.join.phase, !Self.playing(stream.video) else {
            return .none
        }
        return apply(.session(session, .failed(.timeout)), in: &state)
    }

    private func startRemembering(_ state: inout State) -> Effect<Action> {
        guard state.remember == nil, let peer = state.verifiedHost, state.hostName == nil else {
            return .none
        }
        state.remember = KakusanRememberFeature.State(subject: .verified(peer))
        return .none
    }

    private func remembered(_ saved: KakusanPeer?, in state: inout State) -> Effect<Action> {
        state.remember = nil
        if let saved, saved.publicKey == state.hostPeer?.publicKey {
            state.recognition = .recognised(saved)
        }
        return .none
    }

    private func handle(_ view: Action.View, in state: inout State) -> Effect<Action> {
        switch view {
        case .controlActivated(let control):
            state.controls.select(control)
            return activate(control, in: &state)
        case .backPressed:
            return back(&state)
        case .moved(let step):
            state.controls.move(step)
            return .none
        case .invitationSubmitted:
            return submitTypedInvitation(&state)
        case .codeSubmitted:
            return submitCode(state.code, in: &state)
        case .leaveConfirmed:
            state.leavePrompt = .hidden
            return apply(.leave, in: &state)
        case .leaveDismissed:
            state.leavePrompt = .hidden
            return .none
        case .shareShown:
            guard case .waitingForHost(_, let reply, _) = state.join.phase, state.shareFile == nil else {
                return .none
            }
            let name = KakusanBlockFile.name(for: reply) + "." + KakusanBlockFile.fileExtension
            return .run { [platform] send in
                await platform.offerFile(reply.text, name) { url in
                    await send(.shareFileReady(url))
                }
            }
            .cancellable(id: CancelID.shareFile, cancelInFlight: true)
        }
    }

    private func activate(_ control: KakusanControl, in state: inout State) -> Effect<Action> {
        switch control {
        case .paste:
            return .run { [platform] send in
                await send(.pasted(await platform.paste()))
            }
        case .connect:
            return submitTypedInvitation(&state)
        case .accept:
            return apply(.setDisclosure(!state.disclosureAccepted), in: &state)
        case .create:
            guard case .ended = state.join.phase else {
                return createReply(in: &state)
            }
            state.invitation = ""
            return apply(.back, in: &state)
        case .copy:
            guard case .waitingForHost(_, let reply, _) = state.join.phase else {
                return .none
            }
            state.copied = true
            return .run { [platform] _ in
                await platform.copy(reply.text)
            }
        case .code, .text:
            state.keyboardRequest += 1
            return .none
        case .verify:
            return submitCode(state.code, in: &state)
        case .remember:
            return .send(.startRemembering)
        case .back, .leave, .cancel, .close:
            return back(&state)
        case .expect, .replace, .save, .name:
            return .none
        }
    }

    private func back(_ state: inout State) -> Effect<Action> {
        switch state.join.phase {
        case .previewed, .disclosureAccepted:
            return apply(.back, in: &state)
        default:
            guard KakusanGuestControls.confirmsLeave(state.join.phase) else {
                return apply(.leave, in: &state)
            }
            state.leavePrompt = .confirming
            return .none
        }
    }

    private func submitTypedInvitation(_ state: inout State) -> Effect<Action> {
        guard !state.invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }
        return submitInvitation(state.invitation, in: &state)
    }

    private func handle(_ event: KakusanGuestEvent, in session: UUID,
                        state: inout State) -> Effect<Action> {
        switch event {
        case .hostIdentified(let peer):
            return identified(peer, in: session, state: &state)
        case .replyReady(let block):
            return apply(.session(session, .replyReady(block)), in: &state)
        case .codeReady(let code):
            return apply(.session(session, .codeReady(code)), in: &state)
        case .stateChanged(let change):
            return apply(.session(session, .state(change)), in: &state)
        case .streamReady(let fps):
            return apply(.session(session, .streamReady(fps: fps)), in: &state)
        case .presented(let surface):
            guard state.join.session == session else {
                return .none
            }
            state.surface = surface
            return .none
        case .firstFrame:
            return apply(.session(session, .firstFrame), in: &state)
        case .streamStopped:
            return apply(.session(session, .streamStopped), in: &state)
        }
    }

    private func submitInvitation(_ text: String, in state: inout State) -> Effect<Action> {
        let operation = uuid()
        guard state.join.apply(.preview(.request(operation))) == .accepted else {
            return .none
        }
        guard let block = KakusanBlock(pasted: text) else {
            return apply(.preview(.failed(operation, .invalidBlock)), in: &state)
        }
        return .run { [kakusan] send in
            await send(.previewResult(operation, block, await kakusan.preview(block)))
        }
    }

    private func previewed(
        _ operation: UUID,
        _ block: KakusanBlock,
        _ result: Result<KakusanInvitationPreview, KakusanError>,
        in state: inout State
    ) -> Effect<Action> {
        switch result {
        case .success(let preview) where preview.expiresAt <= date.now:
            return apply(.preview(.failed(operation, .expired)), in: &state)
        case .success(let preview):
            let summary = KakusanInvitationSummary(invitation: block, preview: preview)
            guard state.join.apply(.preview(.succeeded(operation, summary))) == .accepted else {
                return .none
            }
            state.host = .claimed(name: preview.claimedHostName)
            state.recognition = nil
            return .none
        case .failure(let error):
            return apply(.preview(.failed(operation, error)), in: &state)
        }
    }

    private func identified(_ peer: KakusanIdentity, in session: UUID,
                            state: inout State) -> Effect<Action> {
        guard state.join.session == session, state.hostPeer == nil else {
            return .none
        }
        state.host = .proven(peer)
        state.recognition = nil
        let key = peer.publicKey
        return .run { [kakusan] send in
            await send(.recognised(key, (try? await kakusan.recognize(key, nil)) ?? .unknown))
        }
    }

    private func createReply(in state: inout State) -> Effect<Action> {
        guard case .disclosureAccepted(let summary) = state.join.phase else {
            return .none
        }
        let session = uuid()
        state.surface = nil
        let effect = apply(.start(session), in: &state)
        let delay = max(0, summary.preview.expiresAt.timeIntervalSince(date.now))
        return .merge(
            effect,
            .run { [kakusan] send in
                do {
                    let own = (try? await kakusan.loadSettings().stunServers) ?? []
                    if case .failure(let error) = await kakusan.useStunServers(own) {
                        throw error
                    }
                    let configuration = KakusanGuestConfiguration(invitation: summary.invitation)
                    try await kakusan.playGuest(session, configuration) { event in
                        await send(.event(session, event))
                    }
                    try Task.checkCancellation()
                    await send(.playEnded(session))
                } catch is CancellationError {
                } catch {
                    await send(.playFailed(session, error as? KakusanError ?? .internal))
                }
            }
            .cancellable(id: CancelID.session, cancelInFlight: true),
            .run { [clock] send in
                try await clock.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
                await send(.expired(session))
            }
            .cancellable(id: CancelID.expiry, cancelInFlight: true)
        )
    }

    private func submitCode(_ text: String, in state: inout State) -> Effect<Action> {
        guard let code = KakusanCode(text), let session = state.join.session else {
            return .none
        }
        let operation = uuid()
        guard state.join.apply(.session(session, .submitCode(operation))) == .accepted else {
            return .none
        }
        return .run { [kakusan] send in
            await send(.codeResult(session, operation: operation, await kakusan.enterCode(code)))
        }
    }

    private func open(_ state: inout State) -> Effect<Action> {
        let before = state.join.phase
        let opening = apply(.open, in: &state)
        if state.join.phase != before {
            state.joinID = uuid()
        }
        return opening
    }

    private func apply(_ input: KakusanGuestInput, in state: inout State) -> Effect<Action> {
        let before = state.join.phase
        guard state.join.apply(input) == .accepted else {
            return .none
        }
        return .merge(progress(from: before, in: &state) + settle(from: before, in: &state))
    }

    private func progress(from before: KakusanGuestPhase, in state: inout State) -> [Effect<Action>] {
        let after = state.join.phase
        var effects: [Effect<Action>] = []
        if Self.awaitingHost(before), !Self.awaitingHost(after) {
            effects.append(.cancel(id: CancelID.expiry))
        }
        if !Self.verified(before), Self.verified(after) {
            state.verifiedHost = state.hostPeer
        }
        guard case .streaming(let session, let stream) = after else {
            return effects
        }
        if state.streamMenu == nil {
            state.streamMenu = StreamMenuReducer.State(context: .guest)
        }
        switch stream.video {
        case .awaitingFrame where !Self.awaitingFrame(before):
            effects.append(.run { [clock] send in
                try await clock.sleep(for: Self.firstFrameDeadline)
                await send(.firstFrameTimedOut(session))
            }
            .cancellable(id: CancelID.firstFrame, cancelInFlight: true))
        case .playing:
            effects.append(.cancel(id: CancelID.firstFrame))
        case .awaitingStream, .awaitingFrame:
            break
        }
        return effects
    }

    private func settle(from before: KakusanGuestPhase, in state: inout State) -> [Effect<Action>] {
        switch state.join.phase {
        case .leaving(let session):
            state.streamMenu = nil
            return cancellations() + [.run { [kakusan] send in
                await kakusan.stopGuest()
                await send(.stopped(session))
            }]
        case .ended where before.session != nil:
            state.streamMenu = nil
            return cancellations() + [.run { [kakusan] _ in
                await kakusan.stopGuest()
            }]
        case .idle, .entering:
            state.host = .unknown
            state.recognition = nil
            state.verifiedHost = nil
            state.streamMenu = nil
            state.remember = nil
            return []
        default:
            return []
        }
    }

    private func cancellations() -> [Effect<Action>] {
        [.cancel(id: CancelID.session), .cancel(id: CancelID.expiry), .cancel(id: CancelID.firstFrame)]
    }

    private static func awaitingHost(_ phase: KakusanGuestPhase) -> Bool {
        switch phase {
        case .preparingReply, .waitingForHost:
            true
        default:
            false
        }
    }

    private static func verified(_ phase: KakusanGuestPhase) -> Bool {
        switch phase {
        case .admitting, .readying, .streaming:
            true
        default:
            false
        }
    }

    private static func awaitingFrame(_ phase: KakusanGuestPhase) -> Bool {
        guard case .streaming(_, let stream) = phase, case .awaitingFrame = stream.video else {
            return false
        }
        return true
    }

    private static func stage(_ phase: KakusanGuestPhase) -> Int {
        switch phase {
        case .idle:
            0
        case .entering:
            1
        case .previewing:
            2
        case .previewed, .disclosureAccepted:
            3
        case .preparingReply:
            4
        case .waitingForHost:
            5
        case .connecting:
            6
        case .verifying:
            7
        case .admitting, .readying:
            8
        case .streaming:
            9
        case .leaving:
            10
        case .ended:
            11
        }
    }
}
