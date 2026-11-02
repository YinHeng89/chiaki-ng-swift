#if os(macOS)
    import AppKit
    import PlatformUI

    /// Moves AppKit first-responder focus between a window's navigation stops by reading order or by
    /// geometry.
    @MainActor
    struct AppKitFocusMover {
        /// The geometry that orders and ranks stops in AppKit's y-up coordinates.
        let geometry = FocusGeometry.appKit

        /// Moves focus to the next or previous navigation stop in reading order, wrapping at the ends.
        ///
        /// - Parameters:
        ///   - backward: Whether to move to the previous stop.
        ///   - window: The window to move focus in.
        func move(backward: Bool, in window: PlatformWindow) {
            window.recalculateKeyViewLoop()
            let current = AppKitKeyViews.focusView(in: window).flatMap { view in
                AppKitKeyViews.isNavigationStop(view)
                    ? view
                    : nil
            }
            let origin = current.flatMap(AppKitKeyViews.focusFrame)
            let stops = AppKitKeyViews.navigationStops(in: window)
                .map { view in
                    (view: view, frame: AppKitKeyViews.focusFrame(view) ?? .zero)
                }
                .filter { stop in
                    origin.map { origin in
                        FocusGeometry.isSameControl(stop.frame, origin)
                    } != true
                }
            guard !stops.isEmpty else {
                return
            }
            let ordered = orderedStops(stops.map(\.frame), after: origin, backward: backward)
            for index in ordered where window.makeFirstResponder(stops[index].view) {
                return
            }
        }

        /// Moves focus to the nearest navigation stop in a direction.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window to move focus in.
        ///   - belowGlobalY: Only stops below this SwiftUI global y position count, when given.
        ///   - allowUnaligned: Whether a vertical move may reach stops out of line with the focused one.
        ///   - horizontalWeight: How much sideways distance counts against a vertical move.
        /// - Returns: Whether focus moved.
        func moveGeometric(
            _ direction: MenuMoveDirection,
            in window: PlatformWindow,
            belowGlobalY: CGFloat?,
            allowUnaligned: Bool,
            horizontalWeight: CGFloat
        ) -> Bool {
            let limit = belowGlobalY.flatMap { globalY in
                AppKitKeyViews.windowY(fromGlobalY: globalY, in: window)
            }
            window.recalculateKeyViewLoop()
            guard let current = AppKitKeyViews.focusView(in: window),
                  let origin = AppKitKeyViews.focusFrame(current) else {
                return false
            }
            let candidates = stops(in: window).filter { stop in
                stop.view !== current
                    && !FocusGeometry.isSameControl(stop.frame, origin)
                    && limit.map { limit in
                        geometry.isBelow(stop.frame, limit: limit)
                    } != false
            }
            guard let index = geometry.target(
                toward: direction,
                from: origin,
                among: candidates.map(\.frame),
                allowUnaligned: allowUnaligned,
                horizontalWeight: horizontalWeight
            ) else {
                return false
            }
            return window.makeFirstResponder(candidates[index].view)
        }

        /// Focuses the navigation stop nearest to a rectangle.
        ///
        /// - Parameters:
        ///   - target: The window-space rectangle focus should land near.
        ///   - window: The window to move focus in.
        /// - Returns: Whether a stop took focus.
        func focusNearest(to target: CGRect, in window: PlatformWindow) -> Bool {
            window.recalculateKeyViewLoop()
            let candidates = stops(in: window)
            guard let index = FocusGeometry.nearest(to: target, among: candidates.map(\.frame)) else {
                return false
            }
            return window.makeFirstResponder(candidates[index].view)
        }

        /// Steps focus forward until it lands on a control below a window-space y position.
        ///
        /// - Parameters:
        ///   - limit: The y position in window coordinates.
        ///   - window: The window to move focus in.
        func focusEntry(below limit: CGFloat, in window: PlatformWindow) {
            for _ in 0..<24 {
                move(backward: false, in: window)
                guard let frame = AppKitKeyViews.focusFrame(window.firstResponder) else {
                    return
                }
                if frame.height < 120, geometry.isBelow(frame, limit: limit) {
                    return
                }
            }
        }

        private func stops(in window: PlatformWindow) -> [(view: NSView, frame: CGRect)] {
            AppKitKeyViews.navigationStops(in: window).compactMap { view in
                guard let frame = AppKitKeyViews.focusFrame(view), FocusGeometry.isStopSized(frame) else {
                    return nil
                }
                return (view: view, frame: frame)
            }
        }

        private func orderedStops(_ frames: [CGRect], after origin: CGRect?, backward: Bool) -> [Int] {
            let sorted = frames.indices.sorted { first, second in
                geometry.precedes(frames[first], frames[second])
            }
            let ordered = backward
                ? Array(sorted.reversed())
                : sorted
            guard let origin else {
                return Array(ordered.prefix(1))
            }
            let following = ordered.filter { index in
                backward
                    ? geometry.precedes(frames[index], origin)
                    : geometry.precedes(origin, frames[index])
            }
            return following + ordered
        }
    }
#endif
