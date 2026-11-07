import ChiakiClients
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

/// Tracks which stream windows currently have controller focus on the Go to Home screen button.
enum StreamHomeFocus {
    /// The focus identifier of the Go to Home screen button.
    static let action = "Go to Home screen"
    /// The label of the Go to Home screen button.
    static let title: LocalizedStringResource = .playbackProhibitedGoHome

    @MainActor private static let owners = NSHashTable<PlatformWindow>.weakObjects()
    @MainActor private static let holders = NSHashTable<PlatformWindow>.weakObjects()

    /// Whether the notice took the controller from the game in the given window, which it hands back once the
    /// console leaves the screen, even after the Home button gave way to the going home spinner.
    @MainActor static func holdsController(in window: PlatformWindow?) -> Bool {
        window.map { holders.contains($0) } ?? false
    }

    /// Records whether the notice holds the controller in a window, ignoring a `nil` window.
    ///
    /// - Parameters:
    ///   - held: Whether the notice took the controller.
    ///   - window: The stream window the controller belongs to.
    @MainActor static func recordHolding(_ held: Bool, in window: PlatformWindow?) {
        guard let window else {
            return
        }
        if held {
            holders.add(window)
        } else {
            holders.remove(window)
        }
    }

    /// Whether the Home button holds focus in the given window; a `nil` window is never focused.
    @MainActor static func focused(in window: PlatformWindow?) -> Bool {
        window.map { owners.contains($0) } ?? false
    }

    /// Records whether the Home button holds focus in a window, ignoring a `nil` window.
    /// - Parameters:
    ///   - focused: Whether the button is focused.
    ///   - window: The stream window the focus belongs to.
    @MainActor static func record(_ focused: Bool, in window: PlatformWindow?) {
        guard let window else {
            return
        }
        if focused {
            owners.add(window)
        } else {
            owners.remove(window)
        }
    }
}

/// Explains that the console is showing a screen Remote Play may not display, and offers a focusable button
/// that returns the console to its Home screen; Down from the button opens the stream menu.
///
/// The console takes a few seconds to leave the screen, so while the request waits the button gives way to
/// a spinner saying it is going home.
struct DisplayProhibitedNotice: View {
    /// The menu focus binding the Home button registers with.
    let focus: MenuFocusState<String?>.Binding
    /// Whether a Go to Home screen request is waiting for the console.
    var goingHome = false
    /// Sends the console to its Home screen.
    let goHome: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Image(systemName: "eye.slash.fill").font(.title)
                Text(.playbackProhibitedTitle).font(.headline)
                Text(.playbackProhibitedDetail)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(28)
            .glassPanel(.large)
            .allowsHitTesting(false)
            if goingHome {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(.playbackProhibitedGoingHome)
                }
                .font(.callout)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            } else {
                FocusButton(action: goHome) {
                    Label(StreamHomeFocus.title, systemImage: "house")
                        .padding(.horizontal, 6)
                }
                .glassControlStyle()
                .controlSize(.large)
                .menuFocused(focus, equals: StreamHomeFocus.action)
                .environment(\.menuMove) { direction in
                    if direction == .down {
                        NotificationCenter.default.post(
                            name: .focusStreamMenu,
                            object: PlaybackWindowControl.keyWindow
                        )
                    }
                }
            }
        }
    }
}

/// Moves controller focus to the Home button when a prohibited screen appears during play, taking the
/// controller from the game so Cross and Down act on the app while a PS press hands it back to the console,
/// and hands the controller back to the game when the screen goes away.
struct StreamHomeFocusTracking: ViewModifier {
    /// The menu navigator used to check the input gate and whether a controller is driving input.
    @Environment(\.menuNavigator) var navigator
    /// The controller driving menus, which the stream menu takes while the Home button has focus.
    @Environment(\.controllerNavigation) var controllerNavigation
    /// The menu focus binding the Home button registers with.
    let focus: MenuFocusState<String?>.Binding
    /// The stream window this modifier tracks focus for.
    let window: PlatformWindow?
    /// Whether the stream is currently playing.
    let playing: Bool
    /// Whether the console is showing a screen that cannot be streamed.
    let prohibited: Bool
    /// Whether a Go to Home screen request is waiting for the console, which hides the Home button.
    var goingHome = false
    /// Reports that the Home button took the controller from the game, or gave it back.
    var holdController: (Bool) -> Void = { _ in
    }

    /// Wraps the content with the focus tracking handlers.
    func body(content: Content) -> some View {
        content
            .onChange(of: focus.wrappedValue) { _, value in
                StreamHomeFocus.record(value == StreamHomeFocus.action, in: window)
                controllerNavigation?.systemButtonReachesStream = value == StreamHomeFocus.action
                if value != StreamHomeFocus.action, !goingHome {
                    StreamHomeFocus.recordHolding(false, in: window)
                }
            }
            .onDisappear {
                controllerNavigation?.systemButtonReachesStream = false
            }
            .onChange(of: goingHome) { wasGoingHome, goingHome in
                guard wasGoingHome, !goingHome, prohibited, playing,
                      !(navigator?.inputGate.isBlocking ?? false),
                      (navigator?.inputMode.mode ?? .pointer) == .controller else {
                    return
                }
                focus.wrappedValue = StreamHomeFocus.action
                holdController(true)
                StreamHomeFocus.recordHolding(true, in: window)
            }
            .onChange(of: prohibited) { _, prohibited in
                if prohibited, playing {
                    if !(navigator?.inputGate.isBlocking ?? false),
                       (navigator?.inputMode.mode ?? .pointer) == .controller {
                        focus.wrappedValue = StreamHomeFocus.action
                        holdController(true)
                        StreamHomeFocus.recordHolding(true, in: window)
                    }
                    return
                }
                guard !prohibited,
                      StreamHomeFocus.focused(in: window) || StreamHomeFocus.holdsController(in: window)
                else {
                    return
                }
                StreamHomeFocus.record(false, in: window)
                StreamHomeFocus.recordHolding(false, in: window)
                focus.wrappedValue = nil
                holdController(false)
            }
    }
}
