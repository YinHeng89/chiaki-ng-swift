import PlatformUI
import QuartzCore
import SwiftUI

/// The base for platform views that draw decorative animation with Core Animation.
///
/// Subclasses add their layers to ``stage``, which uses a top-left origin on both platforms,
/// and pause or resume them through ``clock``. The view never takes hit tests or user input.
class AmbientLayerHostView: PlatformView {
    /// The layer that holds every animated sublayer and whose timing ``clock`` controls.
    let stage = CALayer()

    /// Pauses and resumes the animations on ``stage``.
    private(set) lazy var clock = AmbientLayerClock(stage: stage)

    /// Creates the view and attaches ``stage`` to its backing layer.
    ///
    /// - Parameter frameRect: The initial frame.
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        #if os(macOS)
            wantsLayer = true
            stage.isGeometryFlipped = true
            layer?.addSublayer(stage)
        #else
            isUserInteractionEnabled = false
            layer.addSublayer(stage)
            registerForTraitChanges([UITraitDisplayScale.self]) { (view: AmbientLayerHostView, _) in
                view.backingChanged()
            }
        #endif
    }

    /// Unsupported; the view is only created in code.
    ///
    /// - Parameter coder: The unarchiver, which is ignored.
    required init?(coder: NSCoder) {
        nil
    }

    /// Whether the animations on ``stage`` are advancing.
    var isAnimating: Bool {
        clock.running
    }

    /// Called after every layout pass; subclasses fit their layers to the new bounds.
    func arrange() {
    }

    /// Called when the display scale may have changed; subclasses re-render bitmaps at ``backingScale``.
    func backingChanged() {
    }

    #if os(macOS)
        /// The number of pixels per point of the window's screen, or of the main screen before the
        /// view joins a window.
        var backingScale: CGFloat {
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        }

        /// Lets every event pass through to the views beneath.
        ///
        /// - Parameter point: The location being tested.
        /// - Returns: Always `nil`.
        override func hitTest(_ point: CGPoint) -> NSView? {
            nil
        }

        /// Lays out the view and then calls ``arrange()``.
        override func layout() {
            super.layout()
            arrange()
        }

        /// Forwards a change of backing properties to ``backingChanged()``.
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            backingChanged()
        }
    #else
        /// The number of pixels per point of the view's trait collection, or 2 before it is known.
        var backingScale: CGFloat {
            let scale = traitCollection.displayScale
            return scale > 0
                ? scale
                : 2
        }

        /// Lays out the subviews and then calls ``arrange()``.
        override func layoutSubviews() {
            super.layoutSubviews()
            arrange()
        }

        /// Calls ``backingChanged()`` because a new window may have a different display scale.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            backingChanged()
        }
    #endif
}

/// Pauses and resumes every animation on a layer by controlling the layer's own timing.
///
/// Pausing freezes the layer's local time; resuming shifts its begin time so the animations
/// continue from the frozen frame rather than jumping ahead by the time spent paused.
@MainActor
final class AmbientLayerClock {
    /// The layer whose local time this clock controls.
    let stage: CALayer

    /// Whether the layer's local time is advancing.
    private(set) var running = true

    /// Creates a running clock for a layer.
    ///
    /// - Parameter stage: The layer whose local time to control.
    init(stage: CALayer) {
        self.stage = stage
    }

    /// The layer's current local time, used as the begin time of newly added animations.
    var now: CFTimeInterval {
        stage.convertTime(CACurrentMediaTime(), from: nil)
    }

    /// Freezes or resumes the layer's local time; setting the current value does nothing.
    ///
    /// - Parameter running: Whether the layer's local time should advance.
    func set(running: Bool) {
        guard running != self.running else {
            return
        }
        self.running = running
        if running {
            let pausedAt = stage.timeOffset
            stage.speed = 1
            stage.timeOffset = 0
            stage.beginTime = 0
            stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        } else {
            let pausedAt = now
            stage.speed = 0
            stage.timeOffset = pausedAt
        }
    }
}
