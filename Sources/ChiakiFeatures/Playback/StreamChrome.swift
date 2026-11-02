import ChiakiModels
import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

extension EnvironmentValues {
    /// The corners whose stream chrome should currently be visible, read by views marked with
    /// `streamChromeCorner(_:)`.
    @Entry var streamChromeVisibleCorners = Set(StreamChromeCorner.allCases)

    /// How much of the stream menu dock shows while the chrome is visible.
    @Entry var streamDock = StreamChromeReducer.Dock.collapsed

    /// The controller buttons that open the stream menu, named in the dock's hint.
    @Entry var streamMenuShortcut = StreamMenuShortcut.standard

    /// Shows the stream menu dock from its handle.
    @Entry var expandStreamDock = StreamDockExpansion {
    }
}

/// Shows the stream menu dock when its handle is hovered or clicked, read from the environment as
/// `expandStreamDock`.
struct StreamDockExpansion {
    private let expand: @MainActor () -> Void

    /// Creates the action.
    ///
    /// - Parameter expand: Shows the dock.
    init(_ expand: @escaping @MainActor () -> Void) {
        self.expand = expand
    }

    /// Shows the dock.
    @MainActor
    func callAsFunction() {
        expand()
    }
}

/// Collects the corners that currently contain a visibly focused chrome control.
struct StreamChromeFocusKey: PreferenceKey {
    /// No corners have focus.
    static let defaultValue = Set<StreamChromeCorner>()
    /// Merges the focused corners reported by sibling views.
    static func reduce(value: inout Set<StreamChromeCorner>, nextValue: () -> Set<StreamChromeCorner>) {
        value.formUnion(nextValue())
    }
}

/// Collects the corners that a view wants pinned open, such as while a menu in that corner is presented.
struct StreamChromePinKey: PreferenceKey {
    /// No corners are pinned.
    static let defaultValue = Set<StreamChromeCorner>()
    /// Merges the pinned corners reported by sibling views.
    static func reduce(value: inout Set<StreamChromeCorner>, nextValue: () -> Set<StreamChromeCorner>) {
        value.formUnion(nextValue())
    }
}

extension View {
    /// Fades this view in and out with the chrome visibility of the given corner and blocks hits while it is
    /// hidden.
    /// - Parameter corner: The corner whose visibility this view follows.
    func streamChromeCorner(_ corner: StreamChromeCorner) -> some View {
        modifier(StreamChromeCornerFade(corner: corner))
    }

    /// Reports the corner as focused while this control shows a visible focus ring, keeping that corner's
    /// chrome up.
    /// - Parameter corner: The corner this control lives in.
    func streamChromeFocus(_ corner: StreamChromeCorner) -> some View {
        modifier(StreamChromeFocusReporter(corner: corner))
    }

    /// Pins the corner's chrome open while `pinned` is true.
    /// - Parameters:
    ///   - corner: The corner to hold visible.
    ///   - pinned: Whether the corner should be held.
    func streamChromePinned(_ corner: StreamChromeCorner, _ pinned: Bool) -> some View {
        transformPreference(StreamChromePinKey.self) { corners in
            if pinned {
                corners.insert(corner)
            }
        }
    }
}

/// Wires a stream view to a `StreamChromeReducer` store: it reports hover, pointer movement, focus and
/// pins, publishes the visible corners to the environment and tells the store when the stream is live.
struct StreamChromePresentation: ViewModifier {
    /// The store that decides chrome and pointer visibility.
    let store: StoreOf<StreamChromeReducer>
    /// Whether the stream is currently live.
    let live: Bool
    @Environment(\.virtualGamepad) private var gamepad
    @Environment(\.inputMode) private var inputMode

    /// Wraps the content with hover tracking on macOS, or a tap that briefly reveals the chrome elsewhere,
    /// plus the focus, pin and live state reporting.
    func body(content: Content) -> some View {
        content
        #if os(macOS)
            .background {
                StreamChromeHoverTracker(
                    pointerHidden: store.pointer == .hidden,
                    changed: { corners in
                        store.send(.hovered(corners))
                    },
                    moved: {
                        store.send(.pointerMoved)
                    },
                    left: {
                        store.send(.pointerLeft)
                    }
                )
            }
        #else
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard gamepad?.usedJustNow != true else {
                        return
                    }
                    store.send(.hovered(Set(StreamChromeCorner.allCases)))
                    store.send(.hovered([]))
                }
            )
        #endif
            .onPreferenceChange(StreamChromeFocusKey.self) { corners in
                Task { @MainActor in
                    store.send(.focused(corners))
                }
            }
            .onPreferenceChange(StreamChromePinKey.self) { corners in
                Task { @MainActor in
                    store.send(.pinned(corners))
                }
            }
            .onChange(of: inputMode, initial: true) { _, mode in
                store.send(.inputModeChanged(mode))
            }
            .environment(\.streamChromeVisibleCorners, store.visibleCorners)
            .environment(\.streamDock, store.dock)
            .environment(\.expandStreamDock, StreamDockExpansion {
                store.send(.dockExpanded)
            })
            .onChange(of: live, initial: true) { _, live in
                store.send(.streaming(live))
            }
    }
}

private struct StreamChromeCornerFade: ViewModifier {
    let corner: StreamChromeCorner
    @Environment(\.streamChromeVisibleCorners) private var visibleCorners
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = visibleCorners.contains(corner)
        content
            .animation(animation(visible)) {
                $0.opacity(
                    visible
                        ? 1
                        : 0
                )
            }
            .allowsHitTesting(visible)
    }

    private func animation(_ visible: Bool) -> Animation? {
        if reduceMotion {
            return nil
        }
        if visible {
            return .easeOut(duration: 0.2)
        }
        return .easeInOut(duration: 0.3)
    }
}

private struct StreamChromeFocusReporter: ViewModifier {
    let corner: StreamChromeCorner
    @MenuFocusState private var focused: Bool
    @Environment(\.inputMode) private var inputMode

    func body(content: Content) -> some View {
        content
            .menuFocusBinding($focused)
            .transformPreference(StreamChromeFocusKey.self) { corners in
                if inputMode.shows(focused) {
                    corners.insert(corner)
                }
            }
    }
}

/// The circular back button in the top leading corner of a screen before its stream plays, such as the Shared
/// Play guest's joining card, which fades with that corner and keeps it visible while focused.
struct StreamChromeBackButton<Focus: Hashable>: View {
    /// The tooltip and accessibility label.
    let title: String
    /// The menu focus binding the button joins.
    let focus: MenuFocusState<Focus?>.Binding
    /// The focus value that identifies this button.
    let focusValue: Focus
    /// Handles a controller move out of the button.
    let move: @MainActor (MenuMoveDirection) -> Void
    /// Runs when the button is pressed.
    let action: () -> Void
    @Environment(\.screenLayout) private var layout

    var body: some View {
        FocusButton(action: action) {
            Image(systemName: "arrow.left")
                .frame(width: 32, height: 32)
        }
        .glassControlStyle()
        .focusBorderShape(.circle)
        .menuFocused(focus, equals: focusValue)
        .environment(\.menuMove, move)
        .help(title)
        .accessibilityLabel(title)
        .streamChromeFocus(.topLeading)
        .padding(.leading, 28 + layout.sideInset)
        .topChromeInset()
        .streamChromeCorner(.topLeading)
    }
}

#if os(macOS)
    /// An invisible AppKit view behind the stream that reports which chrome corners the pointer hovers,
    /// throttled pointer movement and pointer exit, and hides the cursor when asked.
    struct StreamChromeHoverTracker: NSViewRepresentable {
        /// Whether the cursor should be hidden until the mouse moves.
        var pointerHidden = false
        /// Receives the hovered corners whenever they change.
        var changed: @MainActor (Set<StreamChromeCorner>) -> Void
        /// Receives pointer movement, at most once per move interval unless the pointer is hidden.
        var moved: @MainActor () -> Void = {
        }
        /// Runs when the pointer leaves the view.
        var left: @MainActor () -> Void = {
        }

        /// Creates the tracking view.
        func makeNSView(context: Context) -> TrackerView {
            TrackerView()
        }

        /// Passes the latest callbacks and pointer visibility to the tracking view.
        func updateNSView(_ view: TrackerView, context: Context) {
            view.changed = changed
            view.moved = moved
            view.left = left
            view.pointerHidden = pointerHidden
        }

        /// The tracking view that observes the mouse and never takes hits itself.
        final class TrackerView: NSView {
            /// Receives the hovered corners whenever they change.
            var changed: @MainActor (Set<StreamChromeCorner>) -> Void = { _ in
            }
            /// Receives throttled pointer movement.
            var moved: @MainActor () -> Void = {
            }
            /// Runs when the pointer leaves the view.
            var left: @MainActor () -> Void = {
            }
            /// Whether the cursor should be hidden; changing it hides or shows the cursor when the pointer is
            /// over the key window.
            var pointerHidden = false {
                didSet {
                    if pointerHidden != oldValue {
                        applyPointer()
                    }
                }
            }
            private var hovered = Set<StreamChromeCorner>()
            private var trackingArea: NSTrackingArea?
            private var lastMove: TimeInterval = 0
            /// The minimum time between movement reports while the pointer is visible.
            static let moveInterval: TimeInterval = 0.25

            /// Uses a top left origin so corner zones match SwiftUI coordinates.
            override var isFlipped: Bool {
                true
            }

            /// Never takes hits, so clicks reach the stream and the chrome above it.
            override func hitTest(_ point: NSPoint) -> NSView? {
                nil
            }

            /// Replaces the tracking area so it follows the visible rectangle.
            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let trackingArea {
                    removeTrackingArea(trackingArea)
                }
                let area = NSTrackingArea(
                    rect: .zero,
                    options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
                addTrackingArea(area)
                trackingArea = area
            }

            /// Reports the hovered corners and an immediate movement when the pointer enters.
            override func mouseEntered(with event: NSEvent) {
                report(convert(event.locationInWindow, from: nil))
                reportMove(at: event.timestamp, force: true)
            }

            /// Reports the hovered corners and a throttled movement as the pointer moves.
            override func mouseMoved(with event: NSEvent) {
                report(convert(event.locationInWindow, from: nil))
                reportMove(at: event.timestamp, force: false)
            }

            /// Clears the hovered corners and reports that the pointer left.
            override func mouseExited(with event: NSEvent) {
                report(nil)
                lastMove = 0
                left()
            }

            /// Shows the cursor again if the view leaves its window while the cursor is hidden.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if window == nil, pointerHidden {
                    NSCursor.setHiddenUntilMouseMoves(false)
                }
            }

            private func reportMove(at time: TimeInterval, force: Bool) {
                guard force || pointerHidden || time - lastMove >= Self.moveInterval else {
                    return
                }
                lastMove = time
                moved()
            }

            private func applyPointer() {
                guard pointerHidden else {
                    NSCursor.setHiddenUntilMouseMoves(false)
                    return
                }
                guard let window, window.isKeyWindow, NSApp.isActive else {
                    return
                }
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                guard bounds.contains(point) else {
                    return
                }
                NSCursor.setHiddenUntilMouseMoves(true)
            }

            private func report(_ point: CGPoint?) {
                let corners = StreamChromeCorner.corners(at: point, in: bounds.size)
                guard corners != hovered else {
                    return
                }
                hovered = corners
                changed(corners)
            }
        }
    }
#endif
