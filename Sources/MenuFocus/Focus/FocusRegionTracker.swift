import Foundation
import PlatformUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Watches a window's keyboard focus and remembers whether it was last inside a screen region, and when it
/// left.
@MainActor
public final class FocusRegionTracker {
    /// The frame of the most recent focused control that was inside the region, in window coordinates.
    public private(set) var lastFrame: CGRect?
    private var leftAt: ContinuousClock.Instant?
    #if os(macOS)
        private var observation: NSKeyValueObservation?
    #else
        private var observation: Task<Void, Never>?
    #endif
    private weak var window: PlatformWindow?
    private weak var navigator: PlatformMenuNavigator?
    /// The watched region in global SwiftUI coordinates, or `nil` when there is none.
    public var globalRegion: CGRect?

    /// Creates a tracker that watches no window yet.
    public init() {
    }

    /// Starts following focus in a window, resetting the history when the window changes.
    ///
    /// - Parameters:
    /// - window: The window to watch, or `nil` to watch none.
    /// - navigator: The navigator that reports whether a control has focus.
    public func observe(_ window: PlatformWindow?, navigator: PlatformMenuNavigator?) {
        self.navigator = navigator
        guard window !== self.window else {
            return
        }
        endObservation()
        lastFrame = nil
        leftAt = nil
        self.window = window
        guard let window else {
            return
        }
        #if os(macOS)
            observation = window.observe(\.firstResponder, options: [
                .initial,
                .new
            ]) { [weak self] window, _ in
                MainActor.assumeIsolated {
                    self?.record(in: window)
                }
            }
        #else
            observation = Task { @MainActor [weak self, weak window] in
                while !Task.isCancelled, let self, let window {
                    self.record(in: window)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        #endif
    }

    private func endObservation() {
        #if os(iOS)
            observation?.cancel()
        #endif
        observation = nil
    }

    /// Stops watching and forgets the window and focus history.
    public func stop() {
        endObservation()
        window = nil
        lastFrame = nil
        leftAt = nil
    }

    /// Reports whether focus is inside the region now or left it less than an interval ago.
    ///
    /// - Parameter interval: How long after leaving focus still counts as inside.
    /// - Returns: `false` when focus has never been inside the region.
    public func wasInside(within interval: Duration) -> Bool {
        guard lastFrame != nil else {
            return false
        }
        guard let leftAt else {
            return true
        }
        return ContinuousClock.now - leftAt < interval
    }

    /// Reports whether the centre of a frame lies inside the region.
    ///
    /// - Parameters:
    /// - frame: A frame in window coordinates.
    /// - window: The window that holds the frame.
    public func contains(_ frame: CGRect, in window: PlatformWindow) -> Bool {
        guard let globalRegion, let region = Self.windowRect(fromGlobal: globalRegion, in: window) else {
            return false
        }
        return region.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Reports whether a control in the window has focus and that control sits inside the region.
    public func focusIsInside(_ window: PlatformWindow) -> Bool {
        guard navigator?.hasControlFocus(in: window) == true,
              let frame = focusFrame(in: window) else {
            return false
        }
        return contains(frame, in: window)
    }

    private func record(in window: PlatformWindow) {
        guard navigator?.hasControlFocus(in: window) == true,
              let frame = focusFrame(in: window) else {
            return
        }
        if contains(frame, in: window) {
            lastFrame = frame
            leftAt = nil
        } else if leftAt == nil {
            leftAt = .now
        }
    }

    private func focusFrame(in window: PlatformWindow) -> CGRect? {
        #if os(macOS)
            return AppKitKeyViews.focusFrame(AppKitKeyViews.focusView(in: window))
        #else
            return navigator?.focusFrame(in: window)
        #endif
    }

    /// Converts a rectangle from global SwiftUI coordinates to the window's coordinate space.
    ///
    /// - Returns: `nil` when the window has no content view.
    public static func windowRect(fromGlobal rect: CGRect, in window: PlatformWindow) -> CGRect? {
        #if os(macOS)
            guard let content = window.contentView else {
                return nil
            }
            let local = content.isFlipped
                ? rect
                : CGRect(
                    x: rect.minX,
                    y: content.bounds.height - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )
            return content.convert(local, to: nil)
        #else
            return rect
        #endif
    }
}
