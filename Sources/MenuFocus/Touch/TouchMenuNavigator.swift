#if os(iOS)
    import Foundation
    import PlatformUI
    import SwiftUI
    import UIKit

    /// The iOS focus engine, built on focus stops the views register instead of a responder chain.
    ///
    /// Each control bound with ``SwiftUI/View/menuFocused(_:equals:)`` registers a ``MenuFocusStop``.
    /// Directions that no handler takes deliver an arrow key press to the focused stop's node chain, and
    /// geometric moves pick among the registered stops with ``FocusGeometry``. A touch anywhere switches to
    /// pointer mode and hides the focus until a controller is used again.
    @MainActor
    public final class TouchMenuNavigator: MenuNavigator {
        /// The handlers views register to take part in navigation.
        public let handlers = MenuHandlerStack()

        /// The router that delivers non-navigation commands to views.
        public let commands = MenuCommandRouter()

        /// The router that reports every command performed, navigation included, to views that only watch input.
        public let performed = MenuCommandRouter()

        /// The record of presentations that own input.
        public let inputGate = MenuInputGate()

        /// Whether the user is driving the app with a controller or touch.
        public let inputMode: InputModeCenter

        /// Where a single finger is resting, for pressed control states.
        public let touchPress = TouchPress()

        /// Called when focus must be restored in a window and no remembered control is left.
        public var focusFallback: (PlatformWindow) -> Void = { _ in
        }

        /// Never true on iOS, which has no native menus that track controller input.
        public let isTrackingMenu = false

        /// The focus stops the views registered.
        let focusStops = TouchFocusStops()

        private let policy: MenuInputPolicy
        private let diagnostics: MenuFocusDiagnostics
        private let observers = TouchWindowObservers()
        private var released: MenuFocusStop?

        /// Creates a navigator.
        ///
        /// - Parameters:
        ///   - policy: The app's answers about streams and key bindings.
        ///   - inputMode: The input mode to start in.
        ///   - diagnostics: Where to report focus decisions.
        public init(
            policy: MenuInputPolicy,
            inputMode: InputModeCenter = InputModeCenter(),
            diagnostics: MenuFocusDiagnostics = .silent
        ) {
            self.policy = policy
            self.inputMode = inputMode
            self.diagnostics = diagnostics
        }

        /// The key window of the active scene.
        public var activeWindow: PlatformWindow? {
            WindowFocus.keyWindow
        }

        /// Starts watching touches in every window and, in debug builds, runs a navigation script from the
        /// `CHIAKI_NAVIGATION_SCRIPT` environment variable.
        public func start() {
            observers.start(reportingTo: self)
            #if DEBUG
                TouchNavigationScript(navigator: self, policy: policy, diagnostics: diagnostics).run()
            #endif
        }

        /// Stops watching touches and drops every handler and remembered state.
        public func stop() {
            observers.stop()
            released = nil
            handlers.removeAll()
        }

        /// Records a touch in a window, hiding the controller focus when it switches to pointer mode.
        ///
        /// - Parameter window: The window touched.
        func touched(in window: PlatformWindow?) {
            guard inputMode.pointerAction(), let window else {
                return
            }
            releaseFocus(in: [window])
        }

        /// The enabled, laid out stops of a window.
        ///
        /// - Parameter window: The window, or `nil` for every window.
        /// - Returns: The stops.
        public func stops(in window: UIWindow?) -> [MenuFocusStop] {
            focusStops.stops(in: window)
        }

        /// The focused stop of a window.
        ///
        /// - Parameter window: The window.
        /// - Returns: The stop, if one has focus.
        public func focusedStop(in window: UIWindow?) -> MenuFocusStop? {
            focusStops.focusedStop(in: window)
        }

        /// Starts text entry in the focused stop of a window, showing the software keyboard for it.
        ///
        /// - Parameter window: The window.
        public func beginEditing(in window: UIWindow?) {
            focusedStop(in: window)?.edit(true)
        }

        @discardableResult
        private func focus(_ stop: MenuFocusStop) -> Bool {
            guard stop.enabled else {
                return false
            }
            stop.claim()
            return true
        }

        private func clearFocus(in window: UIWindow?) {
            guard let stop = focusedStop(in: window) else {
                return
            }
            stop.edit(false)
            stop.release()
            focusStops.lost(stop)
        }

        @discardableResult
        private func send(_ key: KeyEquivalent, in window: UIWindow?) -> Bool {
            focusedStop(in: window)?.deliver(key) ?? false
        }

        /// Performs a command in the active window, while the app is active.
        ///
        /// - Parameter command: The controller command.
        public func perform(_ command: MenuCommand) {
            guard UIApplication.shared.applicationState == .active, let window = activeWindow else {
                return
            }
            perform(command, in: window)
        }

        /// Performs a command in a window.
        ///
        /// - Parameters:
        ///   - command: The controller command.
        ///   - window: The window to perform it in.
        public func perform(_ command: MenuCommand, in window: PlatformWindow) {
            performed.send(command, to: window)
            if command.isNavigation {
                scheduleFocusReveal(in: window)
            }
            if !command.isNavigation {
                commands.send(command, to: window)
            } else if let direction = command.direction {
                move(direction, in: window)
            } else if command == .confirm {
                confirm(in: window)
            } else if !handlers.back(in: window) {
                send(.escape, in: window)
            }
        }

        private func move(_ direction: MenuMoveDirection, in window: PlatformWindow) {
            if performFocusMove(direction, in: window) {
                return
            }
            guard hasControlFocus(in: window) else {
                _ = restoreFocus(in: window)
                return
            }
            send(direction.key, in: window)
        }

        private func confirm(in window: PlatformWindow) {
            if handlers.activateModal(in: window) || handlers.activate(in: window) {
                return
            }
            guard let stop = focusedStop(in: window) else {
                return
            }
            if stop.isEditing() {
                send(.return, in: window)
                return
            }
            if send(.space, in: window) {
                return
            }
            if !handlers.activateText(in: window) {
                stop.edit(true)
            }
        }

        /// Asks the registered focus move handlers about a direction.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window it belongs to.
        /// - Returns: Whether a handler moved focus.
        public func performFocusMove(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
            handlers.performFocusMove(direction, in: window)
        }

        /// Moves focus to the next or previous stop in reading order, wrapping at the ends.
        ///
        /// - Parameters:
        ///   - backward: Whether to move to the previous stop.
        ///   - window: The window to move focus in.
        public func move(backward: Bool, in window: PlatformWindow) {
            if let target = focusStops.sequential(backward: backward, in: window) {
                focus(target)
            }
        }

        /// Moves focus to the nearest stop in a direction.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window to move focus in.
        ///   - belowGlobalY: Only stops below this global y position count, when given.
        ///   - allowUnaligned: Whether a vertical move may reach stops out of line with the focused one.
        ///   - horizontalWeight: How much sideways distance counts against a vertical move.
        /// - Returns: Whether focus moved.
        @discardableResult
        public func moveGeometric(
            _ direction: MenuMoveDirection,
            in window: PlatformWindow,
            belowGlobalY: CGFloat? = nil,
            allowUnaligned: Bool = false,
            horizontalWeight: CGFloat = 0.1
        ) -> Bool {
            let target = focusStops.geometric(
                direction,
                in: window,
                belowGlobalY: belowGlobalY,
                allowUnaligned: allowUnaligned,
                horizontalWeight: horizontalWeight
            )
            return target.map(focus) ?? false
        }

        /// Whether a control-sized stop has focus in a window.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` when the focused stop is smaller than a container.
        public func hasControlFocus(in window: PlatformWindow) -> Bool {
            guard let stop = focusedStop(in: window) else {
                return false
            }
            return stop.frame.height < FocusGeometry.maximumStopHeight
        }

        /// The focused stop's frame.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The frame in global coordinates, if a stop has focus.
        public func focusFrame(in window: PlatformWindow) -> CGRect? {
            focusedStop(in: window)?.frame
        }

        /// Moves focus to the first stop unless a control already has it.
        ///
        /// - Parameter window: The window to check.
        public func ensureControlFocused(in window: PlatformWindow) {
            if let frame = focusFrame(in: window), frame.height < 120 {
                return
            }
            move(backward: false, in: window)
        }

        /// Focuses the first control below a global y position in reading order.
        ///
        /// - Parameters:
        ///   - globalY: The y position in global coordinates.
        ///   - window: The window to move focus in.
        public func focusEntry(belowGlobalY globalY: CGFloat, in window: PlatformWindow) {
            if let entry = focusStops.entry(belowGlobalY: globalY, in: window) {
                focus(entry)
            }
        }

        /// Focuses the stop nearest to a rectangle.
        ///
        /// - Parameters:
        ///   - target: The global rectangle focus should land near.
        ///   - window: The window to move focus in.
        /// - Returns: Whether a stop took focus.
        @discardableResult
        public func focusNearest(to target: CGRect, in window: PlatformWindow) -> Bool {
            focusStops.nearest(to: target, in: window).map(focus) ?? false
        }

        /// Whether the focused stop is in text entry.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` while the user is typing into the focused field.
        public func isEditingText(in window: PlatformWindow) -> Bool {
            focusedStop(in: window)?.isEditing() ?? false
        }

        /// Scrolls the focused stop into view now and again after the focus change settles.
        ///
        /// - Parameter window: The window whose focus to reveal.
        public func scheduleFocusReveal(in window: PlatformWindow) {
            Task { @MainActor in
                await Task.yield()
                TouchScrollReveal.reveal(focusFrame(in: window), in: window)
                try? await Task.sleep(for: .milliseconds(140))
                TouchScrollReveal.reveal(focusFrame(in: window), in: window)
            }
        }

        /// Hides the controller focus because the user touched the screen, remembering the focused stop.
        ///
        /// - Parameter windows: The windows to release.
        public func releaseFocus(in windows: [PlatformWindow]) {
            for window in windows {
                guard let stop = focusedStop(in: window), !stop.isEditing() else {
                    continue
                }
                released = stop
                clearFocus(in: window)
            }
        }

        /// Shows the controller focus again: the released stop, or the first sensible one.
        ///
        /// - Parameter window: The window to restore focus in.
        /// - Returns: `false` when the window hosts a stream and focus stays with the game.
        @discardableResult
        public func restoreFocus(in window: PlatformWindow) -> Bool {
            inputMode.controllerInput()
            guard !hasControlFocus(in: window) else {
                scheduleFocusReveal(in: window)
                return true
            }
            if let stop = released, stops(in: window).contains(where: { $0 === stop }) {
                released = nil
                focus(stop)
                scheduleFocusReveal(in: window)
                return true
            }
            if policy.hostsStream(window) {
                return false
            }
            focusFallback(window)
            Task { @MainActor in
                await Task.yield()
                if !hasControlFocus(in: window) {
                    move(backward: false, in: window)
                }
                scheduleFocusReveal(in: window)
            }
            return true
        }

        /// Whether the focused stop is in text entry.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` while the user is typing.
        public func acceptsTextInput(in window: PlatformWindow) -> Bool {
            isEditingText(in: window)
        }

        /// Whether any stop has focus, which can open the on-screen keyboard.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` when a stop has focus.
        public func focusAcceptsControllerKeyboard(in window: PlatformWindow) -> Bool {
            focusedStop(in: window) != nil
        }

        /// The focused stop.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The stop, if one has focus.
        public func focusOrigin(in window: PlatformWindow) -> FocusOrigin? {
            focusedStop(in: window)
        }

        /// The focused stop.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The stop, if one has focus.
        public func editingFocusOrigin(in window: PlatformWindow) -> FocusOrigin? {
            focusedStop(in: window)
        }

        /// Returns focus to a remembered stop if it is still registered.
        ///
        /// - Parameters:
        ///   - origin: The stop to focus.
        ///   - window: The window it is in.
        ///   - advance: Whether to move to the next stop afterwards.
        public func restoreFocus(to origin: FocusOrigin, in window: PlatformWindow, advance: Bool) async {
            guard WindowFocus(window).isOnScreen, stops(in: window).contains(where: { $0 === origin }) else {
                return
            }
            focus(origin)
            if advance {
                try? await Task.sleep(for: .milliseconds(60))
                move(backward: false, in: window)
            }
        }

        /// Removes focus from every stop in a window and ends text entry.
        ///
        /// - Parameter window: The window to clear.
        public func resignFocus(in window: PlatformWindow) {
            clearFocus(in: window)
            window.endEditing(true)
        }

        /// Removes focus in the key window without animating, ending text entry.
        public func endEditing() {
            guard let window = activeWindow else {
                return
            }
            UIView.performWithoutAnimation {
                resignFocus(in: window)
            }
        }
    }

    /// The focus stops the views of an iOS app registered, the stop that has focus in each window, and the
    /// stops focus moves to.
    ///
    /// Moves pick among the enabled, laid out stops of a window with ``FocusGeometry/touch``.
    @MainActor
    final class TouchFocusStops {
        /// Every registered stop, in registration order.
        private(set) var registered = [MenuFocusStop]()

        private let geometry = FocusGeometry.touch
        private var focused = [ObjectIdentifier?: MenuFocusStop]()

        /// Registers a focus stop.
        ///
        /// - Parameter stop: The stop.
        func register(_ stop: MenuFocusStop) {
            guard !registered.contains(where: { $0 === stop }) else {
                return
            }
            registered.append(stop)
        }

        /// Removes a focus stop.
        ///
        /// - Parameter stop: The stop.
        func unregister(_ stop: MenuFocusStop) {
            registered.removeAll { $0 === stop }
            lost(stop)
        }

        /// Records that a stop took focus, unfocusing the previous stop in its window.
        ///
        /// - Parameter stop: The stop.
        func gained(_ stop: MenuFocusStop) {
            let window = stop.window.map(ObjectIdentifier.init)
            let previous = focused[window]
            focused[window] = stop
            if let previous, previous !== stop {
                previous.edit(false)
                previous.release()
            }
        }

        /// Records that a stop lost focus.
        ///
        /// - Parameter stop: The stop.
        func lost(_ stop: MenuFocusStop) {
            for (window, current) in focused where current === stop {
                focused[window] = nil
            }
        }

        /// The enabled, laid out stops of a window.
        ///
        /// - Parameter window: The window, or `nil` for every window.
        /// - Returns: The stops.
        func stops(in window: UIWindow?) -> [MenuFocusStop] {
            registered.filter { stop in
                stop.enabled && !stop.frame
                    .isEmpty && (stop.window == nil || window == nil || stop.window === window)
            }
        }

        /// The focused stop of a window.
        ///
        /// - Parameter window: The window.
        /// - Returns: The stop, if one has focus.
        func focusedStop(in window: UIWindow?) -> MenuFocusStop? {
            if let stop = focused[window.map(ObjectIdentifier.init)] {
                return stop
            }
            return focused.values.first { stop in
                stop.window == nil || window == nil
            }
        }

        /// The next or previous stop in reading order, wrapping at the ends.
        ///
        /// - Parameters:
        ///   - backward: Whether to take the previous stop.
        ///   - window: The window.
        /// - Returns: The stop, or `nil` when there is no other stop.
        func sequential(backward: Bool, in window: UIWindow) -> MenuFocusStop? {
            let current = focusedStop(in: window)
            let candidates = stops(in: window).filter { stop in
                stop !== current
            }
            let index = geometry.sequentialTarget(
                after: current?.frame,
                among: candidates.map(\.frame),
                backward: backward
            )
            return index.map { candidates[$0] }
        }

        /// The nearest stop in a direction from the focused stop.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window.
        ///   - belowGlobalY: Only stops below this global y position count, when given.
        ///   - allowUnaligned: Whether a vertical move may reach stops out of line with the focused one.
        ///   - horizontalWeight: How much sideways distance counts against a vertical move.
        /// - Returns: The stop, or `nil` when nothing has focus or no stop lies that way.
        func geometric(
            _ direction: MenuMoveDirection,
            in window: UIWindow,
            belowGlobalY: CGFloat?,
            allowUnaligned: Bool,
            horizontalWeight: CGFloat
        ) -> MenuFocusStop? {
            guard let current = focusedStop(in: window) else {
                return nil
            }
            let origin = current.frame
            let candidates = stops(in: window).filter { stop in
                stop !== current
                    && FocusGeometry.isStopSized(stop.frame)
                    && !FocusGeometry.isSameControl(stop.frame, origin)
                    && (belowGlobalY.map { geometry.isBelow(stop.frame, limit: $0) } ?? true)
            }
            let index = geometry.target(
                toward: direction,
                from: origin,
                among: candidates.map(\.frame),
                allowUnaligned: allowUnaligned,
                horizontalWeight: horizontalWeight
            )
            return index.map { candidates[$0] }
        }

        /// The first control-sized stop below a global y position in reading order.
        ///
        /// - Parameters:
        ///   - globalY: The y position in global coordinates.
        ///   - window: The window.
        /// - Returns: The stop, or `nil` when none lies below.
        func entry(belowGlobalY globalY: CGFloat, in window: UIWindow) -> MenuFocusStop? {
            stops(in: window)
                .filter { stop in
                    stop.frame.height < 120 && geometry.isBelow(stop.frame, limit: globalY)
                }
                .min { first, second in
                    geometry.precedes(first.frame, second.frame)
                }
        }

        /// The stop nearest to a rectangle.
        ///
        /// - Parameters:
        ///   - target: The global rectangle focus should land near.
        ///   - window: The window.
        /// - Returns: The stop, or `nil` when the window has none.
        func nearest(to target: CGRect, in window: UIWindow) -> MenuFocusStop? {
            let candidates = stops(in: window).filter { stop in
                FocusGeometry.isStopSized(stop.frame)
            }
            return FocusGeometry.nearest(to: target, among: candidates.map(\.frame)).map { candidates[$0] }
        }
    }

    /// Scrolls the innermost scroll view under the focused stop so the stop is not cut off.
    ///
    /// Only scroll views that can scroll, overlap the stop, are not text views and do not manage their own
    /// focus scrolling (``SelfManagedFocusScrolling``) are moved. The stop is kept
    /// ``FocusGeometry/revealMargin`` points from the edge, and the scroll animates unless Reduce Motion is
    /// on.
    @MainActor
    enum TouchScrollReveal {
        /// Reveals a focused stop's frame in a window.
        ///
        /// - Parameters:
        ///   - frame: The focused stop's frame in global coordinates, or `nil` when nothing has focus.
        ///   - window: The window.
        static func reveal(_ frame: CGRect?, in window: UIWindow) {
            guard let frame, frame.height < window.bounds.height else {
                return
            }
            var candidates = [(scrollView: UIScrollView, depth: Int)]()
            collectScrollViews(in: window, depth: 0, containing: frame, into: &candidates)
            guard let scrollView = candidates.max(by: { $0.depth < $1.depth })?.scrollView else {
                return
            }
            let margin = FocusGeometry.revealMargin
            let target = scrollView.convert(frame, from: nil).insetBy(dx: -margin, dy: -margin)
            scrollView.scrollRectToVisible(target, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        private static func collectScrollViews(
            in view: UIView,
            depth: Int,
            containing frame: CGRect,
            into candidates: inout [(scrollView: UIScrollView, depth: Int)]
        ) {
            for subview in view.subviews where !subview.isHidden {
                if let scrollView = subview as? UIScrollView,
                   scrollView.isScrollEnabled,
                   scrollView.convert(scrollView.bounds, to: nil).intersects(frame),
                   !scrollView.subviews.contains(where: { $0 is SelfManagedFocusScrolling.Marker }),
                   !(scrollView is UITextView) {
                    candidates.append((scrollView, depth))
                }
                collectScrollViews(in: subview, depth: depth + 1, containing: frame, into: &candidates)
            }
        }
    }

    #if DEBUG
        /// Drives the touch navigator from the `CHIAKI_NAVIGATION_SCRIPT` environment variable in debug builds.
        ///
        /// The script is a comma-separated list of steps, one a second: a controller command (`up`, `confirm`,
        /// `back` and the like), `dump` to log every stop, `edit` to start text entry in the focused stop,
        /// `type:` followed by text to insert, or any other step the app's policy performs. After each command the
        /// focused frame is logged.
        @MainActor
        struct TouchNavigationScript {
            /// The navigator the script drives.
            unowned let navigator: TouchMenuNavigator

            /// The app's answers about steps the navigator does not know.
            let policy: MenuInputPolicy

            /// Where to log the focus after each step.
            let diagnostics: MenuFocusDiagnostics

            /// Runs the script in the environment, if there is one.
            func run() {
                guard let script = ProcessInfo.processInfo.environment["CHIAKI_NAVIGATION_SCRIPT"] else {
                    return
                }
                let commands: [String: MenuCommand] = [
                    "up": .up, "down": .down, "left": .left, "right": .right, "confirm": .confirm,
                    "back": .back, "alternate": .alternate, "previous": .previous, "next": .next,
                    "toolbar": .focusToolbar, "settings": .settings
                ]
                Task { @MainActor in
                    for step in script.split(separator: ",").map(String.init) {
                        try? await Task.sleep(for: .seconds(1))
                        guard runStep(step, commands: commands) else {
                            continue
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                        let window = navigator.activeWindow
                        let frame = window.flatMap(navigator.focusFrame(
                            in:
                        )).map { "\($0.integral)" } ?? "none"
                        diagnostics
                            .log(
                                "Script \(step): focus \(frame) of \(navigator.stops(in: window).count) stops"
                            )
                    }
                }
            }

            private func runStep(_ step: String, commands: [String: MenuCommand]) -> Bool {
                if step == "dump" {
                    let lines = navigator.focusStops.registered.map { stop in
                        "\(stop.frame.integral) \(stop.enabled)"
                    }
                    diagnostics.log("Stops " + lines.joined(separator: " | "))
                    return false
                }
                if step == "edit" {
                    navigator.focusedStop(in: navigator.activeWindow)?.edit(true)
                    return false
                }
                if step.hasPrefix("type:") {
                    ScriptedTextEntry.insert(String(step.dropFirst(5)))
                    return false
                }
                guard let command = commands[step] else {
                    _ = policy.performScriptStep(step)
                    return false
                }
                navigator.inputMode.controllerInput()
                navigator.perform(command)
                return true
            }
        }
    #endif

    #if DEBUG
        /// Types text into whichever responder has focus, for debug navigation scripts.
        @MainActor
        final class ScriptedTextEntry: NSObject {
            private static weak var responder: UIResponder?

            /// Inserts text into the first responder.
            ///
            /// - Parameter text: The text to type.
            static func insert(_ text: String) {
                responder = nil
                UIApplication.shared.sendAction(
                    #selector(UIResponder.chiakiCaptureResponder(_:)),
                    to: nil,
                    from: nil,
                    for: nil
                )
                (responder as? UIKeyInput)?.insertText(text)
            }

            /// Records the responder that answered the capture action.
            ///
            /// - Parameter found: The first responder.
            static func note(_ found: UIResponder) {
                responder = found
            }
        }

        extension UIResponder {
            /// Answers the capture action sent by ``ScriptedTextEntry`` so the first responder can be found.
            ///
            /// - Parameter sender: The action's sender.
            @objc func chiakiCaptureResponder(_ sender: Any?) {
                ScriptedTextEntry.note(self)
            }
        }
    #endif
#endif
