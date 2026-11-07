import Dependencies
import ChiakiModels
import ChiakiDiagnostics
import PlatformUI
import Observation
import SwiftUI
import DesignSystem

/// Notification names used by playback.
extension Notification.Name {
    /// Posted to show or hide the virtual touchpad over the stream in the window in `object`.
    public static let toggleVirtualTouchpad = Notification.Name("ChiakiNG.toggleVirtualTouchpad")
}

/// Drives the on-screen DualSense touchpad, turning pointer or touch input into touchpad output and, on
/// macOS, hosting the two touchpad halves beside the video.
@MainActor @Observable public final class VirtualTouchpadModel {
    /// The touchpad halves' height as a fraction of the video's height.
    static let heightFraction: CGFloat = 0.3
    /// The gap between each half and the video's edge as a fraction of the video's width.
    static let edgeInset: CGFloat = 0.025
    /// How long in seconds the touchpad takes to fade in or out.
    static let fade: TimeInterval = 0.2
    /// The two halves the touchpad is split into.
    static let sides: [TouchpadRegion] = [.left, .right]

    /// The touchpad state machine that tracks visibility and the current gesture.
    public private(set) var pad: VirtualTouchpad
    /// Whether the touchpad may be shown; while it is not, showing, pinning and placing it do nothing.
    public private(set) var isEnabled: Bool
    /// Called whenever ``VirtualTouchpadModel/output`` changes so the new touch can be sent to the console.
    @ObservationIgnored public var changed: () -> Void = {
    }
    /// The touch and click state to send to the console.
    @ObservationIgnored public private(set) var output = VirtualTouchpad.Output.none
    private let logger: LoggerClient
    #if os(macOS)
        @ObservationIgnored private var hosts: [TouchpadRegion: TouchpadHostView] = [:]
        @ObservationIgnored private weak var anchor: PlatformView?
        @ObservationIgnored private var frameObserver: NSObjectProtocol?
    #endif

    /// Creates a hidden touchpad for the given touch surface.
    /// - Parameters:
    ///   - surface: The console touchpad's dimensions.
    ///   - logger: The diagnostic log the touchpad's gesture steps are written to.
    ///   - enabled: Whether the touchpad may be shown.
    public init(surface: TouchpadSurface, logger: LoggerClient, enabled: Bool = true) {
        pad = VirtualTouchpad(surface: surface)
        self.logger = logger
        isEnabled = enabled
    }

    /// Allows or forbids showing the touchpad, hiding it and removing it from the window when forbidden.
    /// - Parameter enabled: Whether the touchpad may be shown.
    public func enable(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }
        isEnabled = enabled
        if !enabled {
            hide()
            detach()
        }
    }

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Shows a hidden touchpad pinned, pins a peeking one, or hides a pinned one.
    public func toggle() {
        guard isEnabled else {
            return
        }
        apply { $0.toggle() }
    }

    /// Shows a hidden touchpad as peeking, for example when the pointer hovers over it.
    public func reveal() {
        guard isEnabled else {
            return
        }
        let time = now
        apply { $0.reveal(at: time) }
    }

    /// Hides the touchpad.
    public func hide() {
        apply { $0.hide() }
    }

    /// Ends the current gesture without hiding the touchpad.
    public func cancel() {
        apply { $0.cancel() }
    }

    /// Advances time-based gesture and auto-hide behaviour.
    public func tick() {
        let time = now
        apply { $0.tick(at: time) }
    }

    /// Feeds a pointer position, starting a touch when no gesture is in progress and moving it otherwise.
    /// - Parameters:
    ///   - x: The horizontal position from 0 to 1 across the whole touchpad.
    ///   - y: The vertical position from 0 to 1.
    public func pointer(x: Double, y: Double) {
        let time = now
        apply { pad in
            switch pad.gesture {
            case .none, .idle, .clicking:
                pad.pointerDown(x: x, y: y, at: time)
            case .ignoring, .pending, .dragging, .holding, .holdDragging:
                pad.pointerMoved(x: x, y: y, at: time)
            }
        }
    }

    /// Ends the current pointer touch.
    public func release() {
        let time = now
        apply { $0.pointerUp(at: time) }
    }

    #if os(macOS)
        /// Reports whether a mouse event falls inside one of the touchpad halves.
        /// - Parameter event: The mouse event to test.
        /// - Returns: `true` when the event lands on the touchpad.
        public func contains(_ event: NSEvent) -> Bool {
            hosts.values.contains { host in
                guard event.window === host.window, let superview = host.superview else {
                    return false
                }
                return host.frame.contains(superview.convert(event.locationInWindow, from: nil))
            }
        }
    #endif

    /// Places the two touchpad halves above the video view and keeps them laid out as it resizes; does
    /// nothing outside macOS.
    /// - Parameter view: The video view the touchpad sits over.
    public func attach(over view: PlatformView) {
        #if os(macOS)
            guard isEnabled, let container = view.superview else {
                return
            }
            if anchor === view, hosts.values.allSatisfy({ $0.superview === container }), !hosts.isEmpty {
                return
            }
            detach()
            for side in Self.sides {
                let content = NSHostingView(rootView: VirtualTouchpadView(model: self, side: side))
                content.sizingOptions = []
                let host = TouchpadHostView(content: content)
                host.hovered = { [weak self] in
                    self?.reveal()
                }
                host.alphaValue = pad.isShown
                    ? 1
                    : 0
                container.addSubview(host, positioned: .above, relativeTo: view)
                hosts[side] = host
            }
            anchor = view
            view.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layout()
                }
            }
            layout()
        #endif
    }

    /// Pins the touchpad on screen, showing it if hidden.
    public func pin() {
        guard isEnabled else {
            return
        }
        apply { pad in
            if pad.presence != .pinned {
                pad.toggle()
            }
        }
    }

    /// Removes the touchpad halves from the window and stops following the video's frame.
    public func detach() {
        #if os(macOS)
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
            hosts.values.forEach {
                $0.removeFromSuperview()
            }
            hosts.removeAll()
            anchor = nil
        #endif
    }

    private func apply(_ transition: (inout VirtualTouchpad) -> Void) {
        var next = pad
        transition(&next)
        guard next != pad else {
            return
        }
        let before = pad.output
        let previous = pad.gesture
        let wasShown = pad.isShown
        pad = next
        if let message = pad.describe(from: previous), !Self.sameStep(previous, pad.gesture) {
            let level: LogLevel = pad.isShown == wasShown
                ? .debug
                : .info
            logger.enqueue(.diagnostic(.controller, level, "Virtual touchpad: \(message)"))
        }
        if pad.isShown != wasShown {
            fade(shown: pad.isShown)
        }
        let after = pad.output
        guard after != before else {
            return
        }
        if let previous = before.touch, let next = after.touch, previous.id != next.id {
            output = .none
            changed()
        }
        output = after
        changed()
    }

    private func fade(shown: Bool) {
        #if os(macOS)
            let alpha: CGFloat = shown
                ? 1
                : 0
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                hosts.values.forEach {
                    $0.alphaValue = alpha
                }
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fade
                hosts.values.forEach {
                    $0.animator().alphaValue = alpha
                }
            }
        #endif
    }

    private static func sameStep(_ first: VirtualTouchpad.Gesture?,
                                 _ second: VirtualTouchpad.Gesture?) -> Bool {
        switch (first, second) {
        case (.pending, .pending), (.dragging, .dragging), (.holding, .holding),
             (.holdDragging, .holdDragging):
            return true
        default:
            return false
        }
    }

    #if os(macOS)
        private func layout() {
            guard let anchor else {
                return
            }
            let video = anchor.frame
            let height = video.height * Self.heightFraction
            let width = height * CGFloat(pad.surface.aspectRatio) / 2
            let inset = video.width * Self.edgeInset
            for (side, host) in hosts {
                host.frame = CGRect(
                    x: side == .left
                        ? video.minX + inset
                        : video.maxX - inset - width,
                    y: video.midY - height / 2,
                    width: width,
                    height: height
                )
            }
        }
    #endif
}

#if os(macOS)
    /// Hosts one SwiftUI touchpad half in AppKit and reports when the pointer enters it.
    final class TouchpadHostView: NSView {
        /// Called when the pointer enters the view.
        var hovered: () -> Void = {
        }

        /// Creates a host that fills itself with the given content view.
        /// - Parameter content: The SwiftUI hosting view to show.
        init(content: NSView) {
            super.init(frame: .zero)
            content.frame = bounds
            content.autoresizingMask = [.width, .height]
            addSubview(content)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        /// Unsupported; this view is created only in code.
        required init?(coder: NSCoder) {
            nil
        }

        /// Reports the pointer entering the touchpad half.
        override func mouseEntered(with event: NSEvent) {
            hovered()
        }
    }
#endif

/// One half of the virtual touchpad, drawn as a glass panel that shows the touch contact and turns accent
/// coloured while clicked.
struct VirtualTouchpadView: View {
    /// The touchpad model that receives drags.
    let model: VirtualTouchpadModel
    /// Which half this view shows.
    let side: TouchpadRegion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var offset: Double {
        side == .left
            ? 0
            : 0.5
    }

    var body: some View {
        GeometryReader { geometry in
            let output = model.pad.output
            let active = model.pad.region == side
            ZStack {
                Rectangle()
                    .fill(fill(active: active, clicked: output.clicked))
                if let touch = output.touch, active {
                    contact(touch, clicked: output.clicked, in: geometry.size)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 18)
                    #if os(macOS)
                        .fill(Color(nsColor: .windowBackgroundColor))
                    #else
                        .fill(Color(uiColor: .systemBackground))
                    #endif
                }
            }
            .glassEffect(AppGlass.control.interactive(), in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        model.pointer(
                            x: offset + value.location.x / max(1, geometry.size.width) / 2,
                            y: value.location.y / max(1, geometry.size.height)
                        )
                    }
                    .onEnded { _ in
                        model.release()
                    }
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.12),
                value: output.clicked
            )
        }
        .accessibilityElement()
        .accessibilityLabel(side == .left
            ? .playbackGamepadTouchpadLeftHalf
            : .playbackGamepadTouchpadRightHalf)
    }

    private func fill(active: Bool, clicked: Bool) -> Color {
        guard active else {
            return .clear
        }
        return clicked
            ? Color.accentColor.opacity(0.32)
            : Color.white.opacity(0.1)
    }

    private func contact(_ touch: ControllerTouch, clicked: Bool, in size: CGSize) -> some View {
        let surface = model.pad.surface
        let diameter: CGFloat = clicked
            ? 26
            : 18
        let x = (Double(touch.x) / Double(surface.width) - offset) * 2
        return Circle()
            .fill(clicked
                ? Color.accentColor
                : Color.white.opacity(0.75))
                .frame(width: diameter, height: diameter)
                .position(
                    x: CGFloat(x) * size.width,
                    y: CGFloat(touch.y) / CGFloat(surface.height) * size.height
                )
                .allowsHitTesting(false)
    }
}
