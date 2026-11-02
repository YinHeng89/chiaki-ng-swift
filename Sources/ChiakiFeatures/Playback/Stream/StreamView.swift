import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The one stream screen for console, cloud and Kakusan guest streams.
///
/// It renders ``StreamFeature`` state and sends intent actions. While the stream starts it shows `starting`
/// for console and guest streams, and the cloud loading screen for cloud streams.
struct StreamView<Starting: View>: View {
    private enum Focus: Hashable {
        case back
        case home
        case retry
        case unpair
    }

    @Environment(\.menuNavigator) private var navigator
    @Environment(\.streamStopTrace) private var stopTrace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The stream.
    let store: StoreOf<StreamFeature>
    /// What console and guest streams show while they start.
    @ViewBuilder let starting: () -> Starting
    @MenuFocusState private var focus: Focus?
    @MenuFocusState private var copyFocused: Bool
    @MenuFocusState private var homeFocus: String?
    @State private var hostWindow: PlatformWindow?

    /// The screen.
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.keyboard)
            StreamSurfaceView(surface: store.surface, videoFit: store.currentVideoFit)
                .ignoresSafeArea(.keyboard)
            reconnecting
            connectionWaiting
            if store.displayProhibited, store.status == .playing {
                DisplayProhibitedNotice(focus: $homeFocus, goingHome: store.homeRequest != .idle) {
                    store.send(.view(.goHome))
                }
            }
            phaseContent
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.status)
        .overlay {
            cloudLoading
        }
        .overlay {
            playingOverlays
        }
        .overlay {
            StreamAccessCodeOverlay(
                phase: store.access,
                playerName: store.access.passcodePad.flatMap { store.couch.accountName(for: $0) },
                submit: { code in
                    store.send(.view(.submitAccessCode(code)))
                },
                cancel: {
                    store.send(.view(.cancelAccess))
                }
            )
        }
        .background(WindowAccessor { hostWindow = $0 })
        .modifier(StreamHomeFocusTracking(
            focus: $homeFocus,
            window: hostWindow,
            playing: store.status == .playing,
            prohibited: store.displayProhibited,
            goingHome: store.homeRequest != .idle,
            holdController: { held in
                store.send(.view(.homeHoldsController(held)))
            }
        ))
        .onChange(of: store.status, initial: true) { _, status in
            updateNavigation(for: status)
        }
        .modifier(StreamNavigationMirror(active: store.controllerNavigationActive))
        .onMenuExitCommand {
            guard !(navigator?.inputGate.isBlocking ?? false) else {
                return
            }
            if !PlaybackWindowControl.leaveFullScreen() {
                requestStop("Escape")
            }
        }
    }
}

extension StreamView {
    @ViewBuilder private var reconnecting: some View {
        if let attempt = store.session.reconnectAttempt {
            VStack(spacing: 10) {
                if store.progress?.progress.previousFailure?.offline == true {
                    Label("No network, waiting to reconnect", systemImage: "wifi.slash")
                        .font(.headline)
                    Text("The stream reconnects once the network is back, for up to 90 seconds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Reconnecting, attempt \(attempt)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                }
                if let operation = store.progress {
                    OperationProgressView(progress: operation)
                }
            }
            .padding(20)
            .glassPanel(.medium)
            .allowsHitTesting(false)
            .accessibilityIdentifier("stream-reconnecting")
        }
    }

    @ViewBuilder private var connectionWaiting: some View {
        if store.connection == .waiting, store.status == .playing, store.session.reconnectAttempt == nil {
            VStack(spacing: 6) {
                Label("Connection lost, waiting…", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text("The stream continues as soon as the console is heard again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .glassPanel(.medium)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stream-connection-waiting")
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch store.status {
        case .connecting:
            if store.session.isRelaunching {
                ProgressView("Restarting the stream")
            } else if store.kind != .cloud {
                starting()
            }
        case .stopping:
            ProgressView("Closing session")
        case .failed:
            failure
                .transition(.opacity)
        case .idle, .playing:
            EmptyView()
        }
    }

    @ViewBuilder private var failure: some View {
        VStack(spacing: 20) {
            Text(store.kind == .cloud
                ? "Cloud connection stopped"
                : "Connection stopped")
                .font(.title2.weight(.semibold))
            CopyableErrorMessage(message: store.failureMessage ?? "", copyFocus: $copyFocused)
                .environment(\.menuMove) { direction in
                    if direction == .down {
                        focus = store.unpair == nil
                            ? failureFocus
                            : .unpair
                    }
                }
            if let offer = store.unpair {
                FocusButton("Unpair", systemImage: "link") {
                    store.send(.view(.unpair))
                }
                .glassControlStyle()
                .menuFocused($focus, equals: .unpair)
                .environment(\.menuMove) { direction in
                    if direction == .up {
                        copyFocused = true
                    } else if direction == .down {
                        focus = .back
                    }
                }
                .disabled(offer.phase == .unpairing)
                if offer.phase == .refused {
                    Text("The pairing couldn’t be removed. Try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                FocusButton(titles.back) {
                    stopTrace.record(traceOwner, "the failure screen's \(titles.back)")
                    store.send(.stop)
                }
                .glassControlStyle()
                .menuFocused($focus, equals: .back)
                .environment(\.menuMove) { direction in
                    if direction == .right, store.offersRetry {
                        focus = .retry
                    } else if direction == .up {
                        focusAboveButtons()
                    }
                }
                if store.offersRetry {
                    FocusButton("Try again") {
                        store.send(.retry)
                    }
                    .glassProminentControlStyle()
                    .menuFocused($focus, equals: .retry)
                    .environment(\.menuMove) { direction in
                        if direction == .left {
                            focus = .back
                        } else if direction == .up {
                            focusAboveButtons()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 440)
        .padding(32)
        .glassPanel(.large)
    }

    @ViewBuilder private var cloudNotices: some View {
        if let notice = store.closingNotice {
            CloudClosingNoticeView(notice: notice)
                .padding(.top, 28)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
        CloudToastLayer(toasts: store.scope(state: \.toasts, action: \.toasts))
    }

    @ViewBuilder private var playingOverlays: some View {
        if store.status == .playing {
            if store.kind == .cloud {
                cloudNotices
            }
            StreamMenuOverlay(
                store: store.scope(state: \.menu, action: \.menu),
                stopTitle: titles.menuStop,
                couch: store.kind == .guest
                    ? nil
                    : store.scope(state: \.couch, action: \.couch),
                kakusan: store.kind == .console && KakusanBuild.included
                    ? store.scope(state: \.kakusan, action: \.kakusan)
                    : nil,
                microphone: store.offersMicrophone
                    ? store.scope(state: \.microphone, action: \.microphone)
                    : nil,
                invitations: store.scope(state: \.invitations, action: \.invitations),
                trophies: store.scope(state: \.trophies, action: \.trophies)
            )
            if store.kind != .guest {
                let couch = store.scope(state: \.couch, action: \.couch)
                CouchNoticesOverlay(store: couch)
                CouchNewControllerOverlay(store: couch)
                CouchAccountPickerOverlay(store: couch)
                CouchControlsOverlay(store: couch)
            }
            if store.kind == .console {
                if KakusanBuild.included {
                    KakusanHostView(store: store.scope(state: \.kakusan, action: \.kakusan))
                }
                StreamConsoleKeyboard(
                    session: store.keyboard.session,
                    edited: { id, text in
                        store.send(.view(.keyboardEdited(id, text)))
                    },
                    finished: { id, accepted in
                        store.send(.view(.keyboardFinished(id, accepted: accepted)))
                    }
                )
            }
            StreamExitConfirmationOverlay(
                store: store.scope(state: \.menu, action: \.menu),
                stream: traceOwner,
                leaveTitle: titles.confirm
            )
        }
    }

    @ViewBuilder private var cloudLoading: some View {
        if store.kind == .cloud, let screen = loadingScreen, let stage = store.session.stage,
           let step = stage.cloudStep {
            CloudLoadingScreen(
                screen: screen,
                chrome: stage.datacenterChoice?.offer == nil
                    ? .status
                    : .picker,
                leaving: store.loading.isLeaving,
                title: store.cloudTitle?.name ?? "",
                artwork: artworkURL,
                status: CloudStartStatus(step: step, wait: stage.cloudWait, datacenter: store.datacenter)
                    .text,
                activeStep: step.rawValue - 1,
                operation: store.progress,
                cancel: {
                    guard !store.loading.isLeaving else {
                        return
                    }
                    stopTrace.record(.cloud, "the connecting screen's cancel")
                    store.send(.stop)
                },
                picker: {
                    datacenterPicker(stage.datacenterChoice)
                }
            )
        }
    }

    @ViewBuilder private func datacenterPicker(_ choice: CloudDatacenterChoice?) -> some View {
        if let choice, let offer = choice.offer {
            CloudDatacenterLaunchPickerView(
                offer: offer,
                remaining: {
                    if case .offered(_, let remaining) = choice {
                        return remaining
                    }
                    return nil
                }(),
                pending: {
                    if case .sending(_, let name) = choice {
                        return name
                    }
                    return nil
                }(),
                choose: { store.send(.view(.chooseDatacenter($0))) },
                cancel: {
                    stopTrace.record(.cloud, "the datacenter picker's cancel")
                    store.send(.stop)
                }
            )
        }
    }

    private var loadingScreen: StreamLoading.Screen? {
        if let screen = store.loading.screen {
            return screen
        }
        return store.status == .connecting
            ? .card
            : nil
    }

    private var artworkURL: URL? {
        guard let raw = store.cloudTitle?.artwork, let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private var titles: StreamExitTitles {
        StreamExitTitles(store.kind)
    }

    private var traceOwner: StreamStopTrace.Stream {
        store.kind == .cloud
            ? .cloud
            : .console
    }

    /// Moves focus from the failure screen's bottom row to Unpair when it is offered, otherwise to Copy error.
    private func focusAboveButtons() {
        if store.unpair != nil {
            focus = .unpair
        } else {
            copyFocused = true
        }
    }

    private func requestStop(_ source: String) {
        stopTrace.record(traceOwner, source)
        store.send(.view(.requestExit(source)))
    }

    private var failureFocus: Focus {
        store.offersRetry
            ? .retry
            : store.unpair == nil
                ? .back
                : .unpair
    }

    private func updateNavigation(for status: StreamStatus) {
        switch status {
        case .playing, .idle, .stopping:
            focus = nil
        case .connecting:
            break
        case .failed:
            Task { @MainActor in
                await Task.yield()
                guard store.status == .failed else {
                    return
                }
                focus = failureFocus
                navigator?.ensureFocus(in: hostWindow) {} apply: {
                    guard focus == nil, store.status == .failed else {
                        return
                    }
                    focus = failureFocus
                }
            }
        }
    }
}

/// The words the stream screen uses for leaving, for each kind of stream.
private struct StreamExitTitles: Equatable {
    /// The back button and the failure screen's way out.
    public let back: String

    /// The stream menu's stop entry.
    public let menuStop: String

    /// The exit confirmation's leave choice.
    public let confirm: String

    /// The titles for a kind of stream.
    ///
    /// - Parameter kind: The kind of stream; `nil` before one started.
    public init(_ kind: StreamKind?) {
        switch kind {
        case .cloud:
            back = "Back to library"
            menuStop = "End cloud session"
            confirm = "End session"
        case .guest:
            back = "Leave game"
            menuStop = "Leave game"
            confirm = "Leave game"
        case .console, nil:
            back = "Back to console"
            menuStop = "Disconnect"
            confirm = "Disconnect"
        }
    }
}

/// The status line of the cloud loading screen.
private struct CloudStartStatus: Equatable {
    /// The text.
    public let text: String

    /// Words where a cloud start is.
    ///
    /// - Parameters:
    ///   - step: The start step.
    ///   - wait: The wait inside the step, if any.
    ///   - datacenter: The datacenter the core connected to, once known.
    public init(step: CloudStartStep, wait: CloudStartWait?, datacenter: CloudDatacenterSelection?) {
        text = Self.text(step: step, wait: wait, datacenter: datacenter)
    }

    private static func text(
        step: CloudStartStep,
        wait: CloudStartWait?,
        datacenter: CloudDatacenterSelection?
    ) -> String {
        if let datacenter, step == .findingServer || step == .connecting {
            return datacenter.connectingDescription
        }
        switch wait {
        case .datacenter(.sent(let name)) where name != CloudDatacenterLaunchOffer.automaticName:
            return "Connecting to \(name)"
        case .datacenter(.sent), .datacenter(.expired):
            return "Choosing the lowest ping"
        case .queued(let position):
            return "Waiting for a server, place \(position) in the queue"
        case .datacenter, nil:
            break
        }
        switch step {
        case .checking:
            return "Checking access"
        case .preparing:
            return "Preparing game"
        case .findingServer:
            return "Finding a server"
        case .connecting:
            return "Waiting for video"
        }
    }
}

/// The cloud service's warning that it will close the game soon, announced to VoiceOver when it appears or
/// changes.
private struct CloudClosingNoticeView: View {
    /// The warning.
    public let notice: CloudClosingNotice

    /// Creates a cloud closing notice view.
    ///
    /// - Parameter notice: The warning.
    public init(notice: CloudClosingNotice) {
        self.notice = notice
    }

    public var body: some View {
        Label(notice.message, systemImage: "clock.badge.exclamationmark")
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 560)
            .glassEffect(AppGlass.warning, in: .capsule)
            .onAppear {
                AccessibilityNotification.Announcement(notice.message).post()
            }
            .onChange(of: notice) { _, next in
                AccessibilityNotification.Announcement(next.message).post()
            }
    }
}
