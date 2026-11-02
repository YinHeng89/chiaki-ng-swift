import DesignSystem
import PlatformUI
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Draws the accent outline around whichever native AppKit control has focus, for screens built from
/// native controls that cannot use the SwiftUI focus modifiers.
///
/// Place it in an overlay that covers those controls. On iOS it draws nothing.
public struct FocusHighlightOverlay {
    @Environment(\.menuNavigator) private var navigator

    /// Creates the overlay.
    public init() {
    }
}

#if os(macOS)
    extension FocusHighlightOverlay: NSViewRepresentable {
        /// Creates the outline view.
        ///
        /// - Parameter context: The representable context.
        /// - Returns: A new ``FocusHighlightView``.
        public func makeNSView(context: Context) -> FocusHighlightView {
            let view = FocusHighlightView()
            view.inputMode = navigator?.inputMode
            return view
        }

        /// Passes the current input mode source to the outline view.
        ///
        /// - Parameters:
        ///   - view: The outline view.
        ///   - context: The representable context.
        public func updateNSView(_ view: FocusHighlightView, context: Context) {
            view.inputMode = navigator?.inputMode
        }
    }
#else
    extension FocusHighlightOverlay: View {
        /// An empty, hit-transparent view.
        public var body: some View {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
#endif

#if os(macOS)
    /// The AppKit view behind ``FocusHighlightOverlay``: a layer ring that follows the window's first
    /// responder while the app is in controller mode, replacing AppKit's blue focus ring.
    public final class FocusHighlightView: NSView {
        /// Where the view reads the input mode; without one the ring stays hidden.
        public weak var inputMode: InputModeCenter?
        private var observer: NSObjectProtocol?
        private var responderObservation: NSKeyValueObservation?
        private let ring = CALayer()

        /// Lets every click pass through to the controls below.
        ///
        /// - Parameter point: The point being tested.
        /// - Returns: Always `nil`.
        override public func hitTest(_ point: CGPoint) -> NSView? {
            nil
        }

        /// Starts following the new window's first responder and drops the old window's observers.
        ///
        /// - Parameter newWindow: The window the view is moving to.
        override public func viewWillMove(toWindow newWindow: PlatformWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            responderObservation = nil
            guard let newWindow else {
                return
            }
            responderObservation = newWindow.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            wantsLayer = true
            clipsToBounds = false
            layer?.masksToBounds = false
            ring.masksToBounds = false
            ring.borderWidth = 2
            ring.borderColor = NSColor(Palette.accent).withAlphaComponent(0.9).cgColor
            ring.backgroundColor = NSColor(Palette.accent).withAlphaComponent(0.12).cgColor
            ring.opacity = 0
            layer?.addSublayer(ring)
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didUpdateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }

        private func refresh() {
            guard let window, window.isVisible else {
                return
            }
            guard inputMode?.mode == .controller,
                  let target = focusTarget(in: window) else {
                hideRing()
                return
            }
            suppressNativeRing(target)
            if let responder = window.firstResponder as? NSView {
                suppressNativeRing(responder)
            }
            let frame = Self.visibleFrame(of: target, in: self)
            guard bounds.intersects(frame) else {
                hideRing()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.frame = frame
            ring.cornerRadius = Self.cornerRadius(for: target, frame: frame)
            ring.opacity = 1
            CATransaction.commit()
        }

        /// The frame a control visibly occupies, in another view's coordinates, using its alignment rect.
        ///
        /// - Parameters:
        ///   - target: The focused control.
        ///   - view: The view whose coordinates to use.
        /// - Returns: The control's visible frame.
        public static func visibleFrame(of target: NSView, in view: NSView) -> CGRect {
            guard let superview = target.superview else {
                return view.convert(target.bounds, from: target)
            }
            let rect = target.alignmentRect(forFrame: target.frame)
            guard rect.width > 0, rect.height > 0 else {
                return view.convert(target.bounds, from: target)
            }
            return view.convert(rect, from: superview)
        }

        /// The ring's corner radius for a control: round for circular buttons, switches and sliders, at most
        /// six points otherwise.
        ///
        /// - Parameters:
        ///   - target: The focused control.
        ///   - frame: Its visible frame.
        /// - Returns: The corner radius.
        public static func cornerRadius(for target: NSView, frame: CGRect) -> CGFloat {
            let round = min(frame.width, frame.height) / 2
            if let button = target as? NSButton, button.bezelStyle == .circular {
                return round
            }
            if target is NSSwitch || target is NSSlider {
                return round
            }
            return min(6, round)
        }

        private func suppressNativeRing(_ view: NSView) {
            guard view.focusRingType != .none else {
                return
            }
            view.focusRingType = .none
            view.noteFocusRingMaskChanged()
        }

        private func hideRing() {
            guard ring.opacity != 0 else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.opacity = 0
            CATransaction.commit()
        }

        private func focusTarget(in window: PlatformWindow) -> NSView? {
            guard let target = AppKitKeyViews.focusView(in: window),
                  target !== window.contentView,
                  target is NSControl,
                  target.bounds.height < FocusGeometry.maximumStopHeight,
                  target.bounds.width > 0 else {
                return nil
            }
            return target
        }
    }
#endif
