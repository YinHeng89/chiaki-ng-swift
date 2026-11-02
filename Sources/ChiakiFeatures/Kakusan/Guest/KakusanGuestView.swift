import ChiakiModels
import ComposableArchitecture
import MenuFocus
import PlatformUI
import SwiftUI

/// The guest's screen: the joining card, then the shared stream.
struct KakusanGuestView: View {
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.streamStopTrace) private var stopTrace
    /// The focus of the stream chrome's own button.
    enum ChromeFocus: Hashable {
        /// The back button.
        case back
    }

    /// The guest.
    @Bindable var store: StoreOf<KakusanGuestFeature>
    @MenuFocusState private var chromeFocus: ChromeFocus?

    var body: some View {
        ZStack {
            if case .streaming(_, let stream) = store.join.phase {
                streaming(stream)
            } else {
                StreamLoadingBackdrop(background: .ambient)
                KakusanModal(
                    width: 580,
                    dims: false,
                    controls: store.controls,
                    move: { store.send(.view(.moved($0))) },
                    activate: { store.send(.view(.controlActivated($0))) },
                    back: { store.send(.view(.backPressed)) },
                    content: {
                        KakusanGuestCard(store: store)
                    }
                )
            }
            if let remember = store.scope(state: \.remember, action: \.remember.presented) {
                KakusanRememberCard(store: remember, title: "Remember this host")
            }
        }
        .overlay(alignment: .topLeading) {
            if returnsToLibrary {
                StreamChromeBackButton(
                    title: "Back to library",
                    focus: $chromeFocus,
                    focusValue: .back,
                    move: { _ in
                    },
                    action: {
                        store.send(.view(.backPressed))
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(StreamNavigationMirror(active: store.controllerNavigationActive))
        .appConfirmation(leaveConfirmation) {
            store.send(.view(.leaveConfirmed))
        } cancel: {
            store.send(.view(.leaveDismissed))
        }
    }

    private var returnsToLibrary: Bool {
        switch store.join.phase {
        case .entering, .ended:
            store.remember == nil
        default:
            false
        }
    }

    private var leaveConfirmation: AppConfirmation? {
        guard store.leavePrompt == .confirming else {
            return nil
        }
        return AppConfirmation(
            title: "Leave this game?",
            systemImage: "person.badge.minus",
            confirmTitle: "Leave",
            tone: .destructive
        )
    }

    @ViewBuilder
    private func streaming(_ stream: KakusanGuestStream) -> some View {
        let playing = KakusanGuestFeature.playing(stream.video)
        ZStack {
            Color.black
            StreamSurfaceView(surface: store.surface, videoFit: VideoFit())
            if !playing {
                StreamLoadingView(status: "Waiting for video", activeStep: 3, stepCount: 4) {
                    stopTrace.record(.console, "the guest connecting screen's cancel")
                    store.send(.leave)
                }
            }
        }
        .overlay {
            if playing, let menu = store.scope(state: \.streamMenu, action: \.streamMenu) {
                StreamMenuOverlay(store: menu, stopTitle: "Leave game")
                StreamExitConfirmationOverlay(store: menu, stream: .console, leaveTitle: "Leave game")
            }
        }
        .onMenuExitCommand {
            guard !(navigator?.inputGate.isBlocking ?? false) else {
                return
            }
            if !PlaybackWindowControl.leaveFullScreen() {
                requestLeave("Escape")
            }
        }
    }

    private func requestLeave(_ source: String) {
        stopTrace.record(.console, source)
        guard store.streamMenu != nil else {
            store.send(.leave)
            return
        }
        store.send(.streamMenu(.requestExit(source)))
    }
}
