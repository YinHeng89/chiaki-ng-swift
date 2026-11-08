import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// A modal card that confirms leaving a stream, offering to keep playing, disconnect or put the console in
/// rest mode as the stream menu allows, with controller left and right selection.
struct StreamExitConfirmationOverlay: View {
    /// A button on the exit confirmation.
    enum Choice: Equatable {
        /// Keep playing, leave by disconnecting, or leave and put the console in rest mode.
        case stay, leave, rest
    }

    /// The stream menu store that holds the exit request and the allowed exit choices.
    let store: StoreOf<StreamMenuReducer>
    /// Whether a console or cloud stream is being left, which sets the wording and the stop trace.
    let stream: StreamStopTrace.Stream
    /// The title of the plain disconnect choice.
    let leaveTitle: LocalizedStringResource
    @State private var selection = Choice.stay
    @State private var hostWindow: PlatformWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.streamStopTrace) private var stopTrace
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if store.exitRequest != nil {
            ZStack {
                Dimming.standard.color
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 38, height: 38)
                            .glassEffect(AppGlass.control, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stream == .cloud
                                ? .playbackExitCloudTitle
                                : .playbackExitTitle)
                                .font(.title3.weight(.semibold))
                            if store.exitChoices == .restMode {
                                Text(.playbackExitRestModeNote)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(choices, id: \.self) { item in
                            choice(item, title: title(item), role: item == .stay
                                ? nil
                                : .destructive)
                                .modifier(CancelShortcut(enabled: item == .stay))
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: choices.count > 2
                    ? 560
                    : 460)
                    .modalCard(.overlay)
                    .modifier(OverlayCardMargins())
                    .transition(reduceMotion
                        ? .opacity
                        : .scale(scale: 0.96).combined(with: .opacity))
            }
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear {
                selection = .stay
            }
            .menuInputBlocking()
            .menuHandlers(move: handleMove, modalActivate: handleActivation, back: handleBack)
        }
    }

    /// The choices offered for the stream menu's exit options, always starting with keep playing.
    var choices: [Choice] {
        switch store.exitChoices {
        case .disconnect:
            [.stay, .leave]
        case .disconnectOrRestMode:
            [.stay, .leave, .rest]
        case .restMode:
            [.stay, .rest]
        }
    }

    private func title(_ choice: Choice) -> LocalizedStringResource {
        switch choice {
        case .stay:
            .playbackExitKeepPlaying
        case .leave:
            leaveTitle
        case .rest:
            store.exitChoices == .restMode
                ? .playbackExitLeave
                : .playbackExitRestMode
        }
    }

    private func symbol(_ choice: Choice) -> String {
        switch choice {
        case .stay:
            "play.fill"
        case .leave:
            "xmark"
        case .rest:
            "moon.fill"
        }
    }

    private func choice(_ choice: Choice, title: LocalizedStringResource, role: ButtonRole?) -> some View {
        let focused = selection == choice
        let tint = role == .destructive
            ? Color(red: 1.0, green: 0.69, blue: 0.67)
            : Color.primary
        return FocusButton(role: role) {
            perform(choice)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol(choice))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(role == .destructive
                        ? tint
                        : Palette.accent)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .drawsOwnFocusHighlight()
        .menuFocusable(false)
        .foregroundStyle(tint)
        .background(Color.white.opacity(focused
                ? 0.12
                : 0.05), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(focused
                    ? Palette.accent
                    : Color.white.opacity(0.1), lineWidth: focused
                        ? 2.5
                        : 1)
        }
    }

    private func perform(_ choice: Choice) {
        switch choice {
        case .stay:
            store.send(.cancelExit)
        case .leave, .rest:
            if let source = store.exitRequest {
                stopTrace.confirm(stream, source)
            }
            store.send(.confirmExit(choice == .rest
                    ? .restMode
                    : .disconnect))
        }
    }

    /// Whether a navigation command for `window` belongs to the confirmation shown in `host`.
    ///
    /// - Parameters:
    ///   - window: The window the command was sent to.
    ///   - host: The window showing the confirmation, once known.
    /// - Returns: `true` only for the confirmation's own window, so other windows keep their navigation.
    static func owns(_ window: AnyObject, host: AnyObject?) -> Bool {
        guard let host else {
            return false
        }
        return host === window
    }

    private func handleMove(_ window: PlatformWindow, _ direction: MenuMoveDirection) -> Bool {
        guard Self.owns(window, host: hostWindow) else {
            return false
        }
        let options = choices
        guard let index = options.firstIndex(of: selection) else {
            selection = .stay
            return true
        }
        switch direction {
        case .left:
            selection = options[max(0, index - 1)]
        case .right:
            selection = options[min(options.count - 1, index + 1)]
        default:
            break
        }
        return true
    }

    private func handleActivation(_ window: PlatformWindow) -> Bool {
        guard Self.owns(window, host: hostWindow) else {
            return false
        }
        perform(selection)
        return true
    }

    private func handleBack(_ window: PlatformWindow) -> Bool {
        guard Self.owns(window, host: hostWindow) else {
            return false
        }
        perform(.stay)
        return true
    }
}

private struct CancelShortcut: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.cancelAction)
        } else {
            content
        }
    }
}
