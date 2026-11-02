import ChiakiModels
import PlatformUI
import SwiftUI
import GameController

/// The video of a playing stream, fitted to the window.
public struct StreamSurfaceView: View {
    /// The player's video view, once presented.
    let surface: StreamSurface?

    /// How the picture fits.
    var videoFit: VideoFit

    /// Creates the video view.
    ///
    /// - Parameters:
    ///   - surface: The player's video view, once presented.
    ///   - videoFit: How the picture fits.
    public init(surface: StreamSurface?, videoFit: VideoFit = VideoFit()) {
        self.surface = surface
        self.videoFit = videoFit
    }

    /// The video, or nothing before it is presented.
    public var body: some View {
        if let view = surface?.view(as: PlatformView.self) {
            EmbeddedVideoSurface(surface: view, videoFit: videoFit)
            #if os(iOS)
                VirtualGamepadLayer()
            #endif
        }
    }
}

#if os(macOS)
    /// The view controller representable that hosts the stream's video surface on this platform.
    typealias VideoControllerRepresentable = NSViewControllerRepresentable
#else
    /// The view controller representable that hosts the stream's video surface on this platform.
    typealias VideoControllerRepresentable = UIViewControllerRepresentable
#endif

/// Embeds the stream's native video surface in SwiftUI, laying it out to the picture fit and, on macOS,
/// taking keyboard focus once.
private struct EmbeddedVideoSurface: VideoControllerRepresentable {
    /// The platform view that renders decoded video.
    let surface: PlatformView
    /// How the video is fitted within the available space.
    var videoFit = VideoFit()
    #if os(macOS)
        /// Creates the controller whose view hosts the video surface.
        func makeNSViewController(context: Context) -> VideoController {
            VideoController()
        }
        /// Installs the surface in the host if needed, applies the picture fit and, the first time, makes the
        /// host the window's first responder.
        func updateNSViewController(_ controller: VideoController, context: Context) {
            let host = controller.host
            host.videoFit = videoFit
            if host.subviews.first !== surface {
                host.subviews.forEach {
                    $0.removeFromSuperview()
                }
                host.addSubview(surface)
            }
            host.needsLayout = true
            guard !controller.claimedFocus else {
                return
            }
            DispatchQueue.main.async { [weak controller] in
                guard let controller, let window = host.window else {
                    return
                }
                window.makeFirstResponder(host)
                controller.claimedFocus = true
            }
        }
    #else
        /// Creates the controller whose view hosts the video surface.
        func makeUIViewController(context: Context) -> VideoController {
            VideoController()
        }
        /// Installs the surface in the host if needed and applies the picture fit.
        func updateUIViewController(_ controller: VideoController, context: Context) {
            let host = controller.host
            host.videoFit = videoFit
            if host.subviews.first !== surface {
                host.subviews.forEach {
                    $0.removeFromSuperview()
                }
                host.addSubview(surface)
            }
            host.setNeedsLayout()
        }
    #endif
    /// A game controller event view controller hosting the video surface, which keeps controller input going
    /// to the stream instead of driving the interface.
    final class VideoController: GCEventViewController {
        /// The view that holds and lays out the video surface.
        let host = VideoHost()
        #if os(macOS)
            /// Whether the host has already been made first responder, so focus is claimed only once.
            var claimedFocus = false
        #endif

        /// Installs the host as the view and turns off controller-driven interface events.
        override func loadView() {
            controllerUserInteractionEnabled = false
            view = host
        }
    }
    #if os(macOS)
        /// Clips the video surface and positions it to the picture fit, takes key events and toggles full
        /// screen on a double click.
        final class VideoHost: NSView, NSGestureRecognizerDelegate {
            /// The picture fit; changing it schedules a layout.
            var videoFit = VideoFit() {
                didSet {
                    if videoFit != oldValue {
                        needsLayout = true
                    }
                }
            }

            /// Always true, so the host can receive key events for the stream.
            override var acceptsFirstResponder: Bool {
                true
            }

            /// Creates the host with clipping and a double-click gesture that toggles full screen.
            override init(frame frameRect: CGRect) {
                super.init(frame: frameRect)
                clipsToBounds = true
                let doubleClick = NSClickGestureRecognizer(
                    target: self,
                    action: #selector(toggleFullScreen)
                )
                doubleClick.numberOfClicksRequired = 2
                doubleClick.delegate = self
                addGestureRecognizer(doubleClick)
            }

            /// Always fails, because the host is only created in code.
            required init?(coder: NSCoder) {
                nil
            }

            /// Lets the double click begin only when it lands outside the overlay views stacked above the
            /// video surface.
            func gestureRecognizer(
                _ gestureRecognizer: NSGestureRecognizer,
                shouldAttemptToRecognizeWith event: NSEvent
            ) -> Bool {
                let point = convert(event.locationInWindow, from: nil)
                return !subviews.dropFirst().contains { $0.frame.contains(point) }
            }

            @objc private func toggleFullScreen() {
                window?.toggleFullScreen(nil)
            }

            /// Makes the host first responder on a click before passing the event on.
            override func mouseDown(with event: NSEvent) {
                window?.makeFirstResponder(self)
                super.mouseDown(with: event)
            }

            /// Sizes the video surface to the frame the picture fit computes for the current bounds.
            override func layout() {
                super.layout()
                let frame = videoFit.frame(width: bounds.width, height: bounds.height)
                subviews.first?.frame = CGRect(
                    x: frame.originX,
                    y: frame.originY,
                    width: frame.width,
                    height: frame.height
                )
            }
        }
    #else
        /// Clips the video surface and positions it to the picture fit.
        final class VideoHost: UIView {
            /// The picture fit; changing it schedules a layout.
            var videoFit = VideoFit() {
                didSet {
                    if videoFit != oldValue {
                        setNeedsLayout()
                    }
                }
            }

            /// Creates the host with clipping enabled.
            override init(frame: CGRect) {
                super.init(frame: frame)
                clipsToBounds = true
            }

            /// Always fails, because the host is only created in code.
            required init?(coder: NSCoder) {
                nil
            }

            /// Sizes the video surface to the frame the picture fit computes for the current bounds.
            override func layoutSubviews() {
                super.layoutSubviews()
                let frame = videoFit.frame(width: bounds.width, height: bounds.height)
                subviews.first?.frame = CGRect(
                    x: frame.originX,
                    y: frame.originY,
                    width: frame.width,
                    height: frame.height
                )
            }
        }
    #endif
}
