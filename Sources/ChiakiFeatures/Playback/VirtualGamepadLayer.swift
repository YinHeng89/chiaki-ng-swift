import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

#if os(iOS)
    /// Overlays the on-screen controller on an iOS stream, choosing the compact or full layout, hiding it
    /// while a physical controller is in use or another overlay is up, and releasing every virtual input when
    /// it goes away.
    struct VirtualGamepadLayer: View {
        @State private var controllerConnected: Bool?
        @Environment(\.screenLayout) private var layout
        @Environment(\.controllerNavigation) private var controllerNavigation
        @Environment(\.menuNavigator) private var navigator
        @Environment(\.virtualGamepad) private var gamepad
        @Environment(\.virtualGamepadLink) private var link

        private static let restingOpacity = 0.18
        private static let handleBottom: CGFloat = 26
        private static let handleLeftOfCentre: CGFloat = 92
        private static let compactHandleBottom: CGFloat = 61

        var body: some View {
            let touchpad = link.touchpad
            let connected = controllerConnected ?? controllerNavigation?.navigationConnected ?? false
            let physical = connected
                && controllerNavigation?.preferredControllerKey != ControlsConfiguration.keyboardOnlyKey
            let presence = gamepad?.presence ?? .automatic
            let visible = presence.isVisible(controllerConnected: physical)
            let attention = gamepad?.attention ?? .awake
            let yields = gamepad?.yieldsToOverlay ?? false
            ZStack {
                if visible, layout.isCompact {
                    VirtualGamepadCompactView(touchpad: touchpad)
                } else if visible {
                    VirtualGamepadView(touchpad: touchpad)
                } else if let touchpad, touchpad.pad.isShown {
                    VirtualTouchpadEdges(model: touchpad)
                }
            }
            .modifier(VirtualGamepadScale())
            .padding(.top, layout.touch
                ? layout.topChromeInset
                : 0)
                .overlay(alignment: .bottom) {
                    VirtualGamepadHandle(shown: visible) {
                        gamepad?.send(.presenceToggled(controllerConnected: physical))
                    }
                    .virtualSecondary(lit: !visible || !layout.isCompact || gamepad?.secondary == .lit)
                    .padding(.bottom, layout.isCompact
                        ? Self.compactHandleBottom
                        : Self.handleBottom + layout.bottomInset)
                        .offset(x: layout.isCompact
                            ? 0
                            : -Self.handleLeftOfCentre)
                }
                .opacity(
                    attention == .awake
                        ? 1
                        : Self.restingOpacity
                )
                .animation(
                    attention == .awake
                        ? .easeOut(duration: 0.15)
                        : .easeInOut(duration: 0.8),
                    value: attention
                )
                .opacity(
                    yields
                        ? 0
                        : 1
                )
                .allowsHitTesting(!yields)
                .onChange(of: navigator?.inputGate.isBlocking ?? false, initial: true) { _, blocking in
                    gamepad?.send(.overlayBlockingChanged(blocking))
                }
                .onChange(of: visible, initial: true) { _, shown in
                    if shown {
                        gamepad?.send(.touched)
                    }
                }
                .onAppear {
                    gamepad?.send(.appeared)
                }
                .onReceive(NotificationCenter.default.publisher(for: .controllerFamilyChanged)) { _ in
                    let connected = controllerNavigation?.navigationConnected ?? false
                    controllerConnected = connected
                    if connected {
                        gamepad?.send(.releasedAll)
                    }
                }
                .onDisappear {
                    gamepad?.send(.disappeared)
                }
        }
    }

    #if DEBUG
        /// A debug-only modifier that shows the on-screen controller over a dimmed screen while it is being
        /// previewed, with its own touchpad.
        struct VirtualGamepadPreview: ViewModifier {
            @State private var touchpad = VirtualTouchpadModel(surface: .ps5, logger: .disabled)
            @Environment(\.screenLayout) private var layout
            @Environment(\.virtualGamepad) private var gamepad
            @Environment(\.virtualGamepadLink) private var link

            /// Overlays the previewed controller layout on the content and lends it a touchpad while preview
            /// is on.
            func body(content: Content) -> some View {
                content.overlay {
                    if gamepad?.previewing == true {
                        ZStack {
                            Color.black.opacity(0.45)
                            Group {
                                if layout.isCompact {
                                    VirtualGamepadCompactView(touchpad: touchpad)
                                } else {
                                    VirtualGamepadView(touchpad: touchpad)
                                }
                            }
                            .modifier(VirtualGamepadScale())
                            .padding(.top, layout.touch
                                ? layout.topChromeInset
                                : 0)
                        }
                        .ignoresSafeArea()
                    }
                }
                .onChange(of: gamepad?.previewing ?? false) { _, previewing in
                    if previewing {
                        gamepad?.send(.secondaryRevealed)
                        link.attach(touchpad)
                        gamepad?.send(.touchpadAttached)
                    } else if link.detach(touchpad) {
                        gamepad?.send(.touchpadDetached)
                    }
                }
            }
        }
    #endif

    /// Draws the on-screen controller in design units and scales it to the screen, never so small that a
    /// control's hit area drops below a finger's target.
    struct VirtualGamepadScale: ViewModifier {
        /// The most points one design unit takes.
        static let pointsPerUnit: CGFloat = 0.72
        /// The design height the layout was drawn for, in design units.
        static let designHeight: CGFloat = 580
        /// The smallest hit area of a control, in design units.
        static let minimumTarget: CGFloat = 62
        /// The fewest points one design unit takes, so ``minimumTarget`` renders at the screen layout's `touchTarget`.
        static let minimumPointsPerUnit = ScreenLayout.touchTarget / minimumTarget

        /// Lays the content out in design units for the available size and scales it to points.
        func body(content: Content) -> some View {
            GeometryReader { proxy in
                let scale = max(
                    Self.minimumPointsPerUnit, min(Self.pointsPerUnit, proxy.size.height / Self.designHeight)
                )
                content
                    .frame(
                        width: proxy.size.width / scale,
                        height: proxy.size.height / scale
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private struct VirtualGamepadHandle: View {
        let shown: Bool
        let toggle: () -> Void

        var body: some View {
            Image(systemName: "gamecontroller")
                .modifier(VirtualPadSurface(
                    pressed: false, shape: .capsule, width: 52, height: 26,
                    hitTarget: ScreenLayout.touchTarget
                ))
                .opacity(
                    shown
                        ? 1
                        : 0.55
                )
                .onTapGesture(perform: toggle)
                .accessibilityLabel(
                    shown
                        ? "Hide on-screen controller"
                        : "Show on-screen controller"
                )
                .accessibilityAddTraits(.isButton)
        }
    }

    private struct VirtualTouchpadEdges: View {
        let model: VirtualTouchpadModel

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let height = size.height * VirtualTouchpadModel.heightFraction
                let width = height * CGFloat(model.pad.surface.aspectRatio) / 2
                let inset = size.width * VirtualTouchpadModel.edgeInset
                ZStack {
                    VirtualTouchpadView(model: model, side: .left)
                        .frame(width: width, height: height)
                        .position(x: inset + width / 2, y: size.height / 2)
                    VirtualTouchpadView(model: model, side: .right)
                        .frame(width: width, height: height)
                        .position(x: size.width - inset - width / 2, y: size.height / 2)
                }
            }
        }
    }

    private struct VirtualGamepadView: View {
        let touchpad: VirtualTouchpadModel?
        @Environment(\.virtualGamepad) private var gamepad

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let upper = size.height - 274
                let lower = size.height - 104
                ZStack {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            gamepad?.send(.secondaryRevealed)
                        }
                    Group {
                        shoulders(in: size, upper: upper)
                        directions(at: CGPoint(x: 186, y: upper))
                    }
                    .virtualSecondary(lit: gamepad?.secondary == .lit)
                    actions(at: CGPoint(x: size.width - 186, y: upper))
                    if let touchpad, touchpad.pad.isShown {
                        surfaces(touchpad, in: size, at: upper)
                    }
                    VirtualStick(stick: .left)
                        .position(x: 378, y: lower)
                    VirtualStick(stick: .right)
                        .position(x: size.width - 378, y: lower)
                    VirtualPadButton(
                        control: .leftStickButton,
                        text: "L3",
                        shape: .circle,
                        width: 44,
                        height: 44
                    )
                    .position(x: 262, y: size.height - 36)
                    VirtualPadButton(
                        control: .rightStickButton,
                        text: "R3",
                        shape: .circle,
                        width: 44,
                        height: 44
                    )
                    .position(x: size.width - 262, y: size.height - 36)
                    centre(in: size, upper: upper, lower: lower)
                }
            }
        }

        private func surfaces(_ model: VirtualTouchpadModel, in size: CGSize,
                              at upper: CGFloat) -> some View {
            let inner: CGFloat = 300
            let width = (size.width - inner * 2 - 6) / 2
            return HStack(spacing: 6) {
                VirtualTouchpadView(model: model, side: .left)
                    .frame(width: width, height: 156)
                VirtualTouchpadView(model: model, side: .right)
                    .frame(width: width, height: 156)
            }
            .position(x: size.width / 2, y: upper)
        }

        private func shoulders(in size: CGSize, upper: CGFloat) -> some View {
            ZStack {
                VirtualPadButton(control: .leftTrigger, text: "L2", shape: .trigger, width: 128, height: 50)
                    .position(x: 186, y: upper - 262)
                VirtualPadButton(control: .leftShoulder, text: "L1", shape: .bumper, width: 128, height: 36)
                    .position(x: 186, y: upper - 200)
                VirtualPadButton(control: .rightTrigger, text: "R2", shape: .trigger, width: 128, height: 50)
                    .position(x: size.width - 186, y: upper - 262)
                VirtualPadButton(control: .rightShoulder, text: "R1", shape: .bumper, width: 128, height: 36)
                    .position(x: size.width - 186, y: upper - 200)
            }
        }

        private func centre(in size: CGSize, upper: CGFloat, lower: CGFloat) -> some View {
            ZStack {
                centreControls(in: size, upper: upper, lower: lower)
                    .virtualSecondary(lit: gamepad?.secondary == .lit)
                VirtualMenuButton()
                    .position(x: size.width / 2, y: lower + 62)
            }
        }

        private func centreControls(in size: CGSize, upper: CGFloat, lower: CGFloat) -> some View {
            ZStack {
                VirtualTouchpadButton(touchpad: touchpad)
                    .position(x: size.width / 2, y: upper - 246)
                VirtualPadButton(control: .share, shape: .capsule, width: 22, height: 46)
                    .position(x: size.width / 2 - 148, y: upper - 252)
                VirtualPadButton(control: .options, shape: .capsule, width: 22, height: 46)
                    .position(x: size.width / 2 + 148, y: upper - 252)
                VirtualTouchpadToggle(touchpad: touchpad)
                    .position(x: size.width / 2, y: upper - 184)
                VirtualPadButton(
                    control: .system,
                    symbol: "playstation.logo",
                    shape: .circle,
                    width: 52,
                    height: 52
                )
                .position(x: size.width / 2, y: lower)
            }
        }

        private func directions(at centre: CGPoint) -> some View {
            let reach: CGFloat = 50
            return ZStack {
                VirtualPadButton(control: .dpadUp, shape: .direction(.up), width: 54, height: 62)
                    .position(x: centre.x, y: centre.y - reach)
                VirtualPadButton(control: .down, shape: .direction(.down), width: 54, height: 62)
                    .position(x: centre.x, y: centre.y + reach)
                VirtualPadButton(control: .left, shape: .direction(.left), width: 62, height: 54)
                    .position(x: centre.x - reach, y: centre.y)
                VirtualPadButton(control: .right, shape: .direction(.right), width: 62, height: 54)
                    .position(x: centre.x + reach, y: centre.y)
            }
        }

        private func actions(at centre: CGPoint) -> some View {
            let reach: CGFloat = 62
            return ZStack {
                VirtualPadButton(
                    control: .triangle,
                    symbol: "triangle",
                    shape: .circle,
                    width: 62,
                    height: 62
                )
                .position(x: centre.x, y: centre.y - reach)
                VirtualPadButton(control: .cross, symbol: "xmark", shape: .circle, width: 62, height: 62)
                    .position(x: centre.x, y: centre.y + reach)
                VirtualPadButton(control: .square, symbol: "square", shape: .circle, width: 62, height: 62)
                    .position(x: centre.x - reach, y: centre.y)
                VirtualPadButton(control: .circle, symbol: "circle", shape: .circle, width: 62, height: 62)
                    .position(x: centre.x + reach, y: centre.y)
            }
        }
    }

    /// The outlines used for on-screen controller buttons, from round face buttons to D-pad arrows and arcs
    /// around a stick.
    enum VirtualPadShape: Shape {
        /// A round button, used for face and stick buttons.
        case circle
        /// A pill, used for system buttons and the controller handle.
        case capsule
        /// A touchpad outline with tighter top corners and rounder bottom corners.
        case touchpad
        /// A rounded rectangle for L1 and R1.
        case bumper
        /// A rectangle with rounder top corners for L2 and R2.
        case trigger
        /// A D-pad arrow pointing in the given direction.
        case direction(MenuMoveDirection)
        /// A stroked band along a circle of the given radius between two angles in degrees, centred in the
        /// frame.
        case arc(radius: CGFloat, from: Double, until: Double)

        /// The thickness of an arc band, also used to size an arc button's frame.
        static let arcWidth: CGFloat = 40

        /// Draws the outline fitted to the given frame.
        func path(in rect: CGRect) -> Path {
            switch self {
            case let .arc(radius, from, until):
                Self.arc(in: rect, radius: radius, from: from, until: until)
            case .circle:
                Path(ellipseIn: rect)
            case .capsule:
                Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
            case .touchpad:
                Path(
                    roundedRect: rect,
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 14, bottomLeading: 28, bottomTrailing: 28, topTrailing: 14
                    )
                )
            case .bumper:
                Path(roundedRect: rect, cornerRadius: 12)
            case .trigger:
                Path(
                    roundedRect: rect,
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 24, bottomLeading: 10, bottomTrailing: 10, topTrailing: 24
                    )
                )
            case .direction(let direction):
                Self.arrow(in: rect, pointing: direction)
            }
        }

        private static func arc(in rect: CGRect, radius: CGFloat, from: Double, until: Double) -> Path {
            var line = Path()
            line.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: radius,
                startAngle: .degrees(from),
                endAngle: .degrees(until),
                clockwise: false
            )
            return line.strokedPath(StrokeStyle(lineWidth: arcWidth, lineCap: .round))
        }

        private static func arrow(in rect: CGRect, pointing direction: MenuMoveDirection) -> Path {
            let length = max(rect.width, rect.height)
            let breadth = min(rect.width, rect.height)
            let shoulder = length * 0.62
            let radius: CGFloat = 9
            var path = Path()
            path.move(to: CGPoint(x: radius, y: 0))
            path.addLine(to: CGPoint(x: breadth - radius, y: 0))
            path.addQuadCurve(to: CGPoint(x: breadth, y: radius), control: CGPoint(x: breadth, y: 0))
            path.addLine(to: CGPoint(x: breadth, y: shoulder))
            path.addLine(to: CGPoint(x: breadth / 2, y: length))
            path.addLine(to: CGPoint(x: 0, y: shoulder))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
            path.closeSubpath()
            let turned: CGAffineTransform
            switch direction {
            case .up:
                turned = .identity
            case .down:
                turned = CGAffineTransform(translationX: breadth, y: length).rotated(by: .pi)
            case .left:
                turned = CGAffineTransform(translationX: 0, y: breadth).rotated(by: -.pi / 2)
            case .right:
                turned = CGAffineTransform(translationX: length, y: 0).rotated(by: .pi / 2)
            }
            return path
                .applying(turned)
                .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
    }

    /// Gives an on-screen controller control its fixed size and clear Liquid Glass in its own shape, lights the
    /// glass white and presses it in while pressed, and limits hit testing to its shape, widened to a finger's
    /// target around a control drawn smaller than one.
    ///
    /// With Reduce Motion on, a press only lights the glass.
    struct VirtualPadSurface: ViewModifier {
        /// Whether the control is drawn as pressed.
        let pressed: Bool
        /// The outline that shapes the glass and hit area.
        let shape: VirtualPadShape
        /// The control's width in design units.
        let width: CGFloat
        /// The control's height in design units.
        let height: CGFloat
        /// The smallest side of the control's hit area, in the same units as ``width`` and ``height``.
        var hitTarget = VirtualGamepadScale.minimumTarget
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hitInsets: CGSize {
            CGSize(width: max(0, (hitTarget - width) / 2), height: max(0, (hitTarget - height) / 2))
        }

        /// Styles the content as an on-screen controller control.
        @ViewBuilder
        func body(content: Content) -> some View {
            let surface = content
                .font(.system(size: min(width, height) * 0.4, weight: .regular))
                .foregroundStyle(.white.opacity(
                    pressed
                        ? 1
                        : 0.8
                ))
                .frame(width: width, height: height)
                .glassEffect(
                    pressed
                        ? AppGlass.control.tint(.white.opacity(0.6))
                        : AppGlass.control,
                    in: shape
                )
                .scaleEffect(
                    pressed && !reduceMotion
                        ? 0.88
                        : 1
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(duration: 0.18, bounce: 0.35),
                    value: pressed
                )
            if hitInsets == .zero {
                surface
                    .contentShape(shape)
            } else {
                surface
                    .padding(.horizontal, hitInsets.width)
                    .padding(.vertical, hitInsets.height)
                    .contentShape(.rect)
            }
        }
    }

    /// An on-screen button that holds a console control down while touched, with a light haptic on press.
    struct VirtualPadButton: View {
        /// The console control the button presses.
        let control: PlayStationControl
        /// The SF Symbol to show, which takes precedence over `text`.
        var symbol: String?
        /// The text to show when there is no symbol.
        var text: String?
        /// The button outline.
        let shape: VirtualPadShape
        /// The button's width in points.
        let width: CGFloat
        /// The button's height in points.
        let height: CGFloat
        @Environment(\.virtualGamepad) private var gamepad

        var body: some View {
            let pressed = gamepad?.pad.holds(control) == true
            label
                .modifier(VirtualPadSurface(pressed: pressed, shape: shape, width: width, height: height))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard gamepad?.pad.holds(control) != true else {
                                return
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            gamepad?.send(.pressed(control, down: true))
                        }
                        .onEnded { _ in
                            gamepad?.send(.pressed(control, down: false))
                        }
                )
                .accessibilityLabel(control.label)
                .accessibilityAddTraits(.isButton)
        }

        @ViewBuilder private var label: some View {
            if let symbol {
                Image(systemName: symbol)
            } else if let text {
                Text(text)
            } else {
                Color.clear
            }
        }
    }

    private struct VirtualTouchpadButton: View {
        private enum Touch: Equatable {
            case idle
            case clicking
            case swiping
        }

        let touchpad: VirtualTouchpadModel?
        @State private var touch = Touch.idle
        @Environment(\.virtualGamepad) private var gamepad

        var body: some View {
            Color.clear
                .modifier(VirtualPadSurface(
                    pressed: gamepad?.pad.holds(.touchpad) == true, shape: .touchpad, width: 230, height: 62
                ))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let travel = hypot(value.translation.width, value.translation.height)
                            switch touch {
                            case .idle:
                                touch = .clicking
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                gamepad?.send(.pressed(.touchpad, down: true))
                            case .clicking:
                                guard travel > 14 else {
                                    return
                                }
                                touch = .swiping
                                gamepad?.send(.pressed(.touchpad, down: false))
                                touchpad?.pin()
                            case .swiping:
                                gamepad?.send(.touched)
                                gamepad?.send(.secondaryRevealed)
                            }
                        }
                        .onEnded { _ in
                            gamepad?.send(.pressed(.touchpad, down: false))
                            touch = .idle
                        }
                )
                .accessibilityLabel("Touchpad")
                .accessibilityHint("Tap to click. Swipe to show the touch surface.")
                .accessibilityAddTraits(.isButton)
        }
    }

    private struct VirtualTouchpadToggle: View {
        let touchpad: VirtualTouchpadModel?
        @Environment(\.virtualGamepad) private var gamepad

        var body: some View {
            let shown = touchpad?.pad.isShown ?? false
            Image(systemName: "hand.draw")
                .modifier(VirtualPadSurface(pressed: shown, shape: .circle, width: 38, height: 38))
                .onTapGesture {
                    gamepad?.send(.touched)
                    touchpad?.toggle()
                }
                .accessibilityLabel(
                    shown
                        ? "Hide touchpad"
                        : "Show touchpad"
                )
                .accessibilityAddTraits(.isButton)
        }
    }

    /// An on-screen button that opens the stream menu when released.
    struct VirtualMenuButton: View {
        @GestureState private var pressed = false
        @Environment(\.menuNavigator) private var navigator
        @Environment(\.virtualGamepad) private var gamepad

        var body: some View {
            Image(systemName: "ellipsis")
                .modifier(VirtualPadSurface(pressed: pressed, shape: .capsule, width: 46, height: 20))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($pressed) { _, pressed, _ in
                            pressed = true
                        }
                        .onEnded { _ in
                            gamepad?.send(.touched)
                            navigator?.perform(.streamMenu)
                        }
                )
                .accessibilityLabel("Stream menu")
                .accessibilityAddTraits(.isButton)
        }
    }

    /// An on-screen thumbstick that follows a drag, springs back on release, and double-taps to click the
    /// stick when a click control is set.
    struct VirtualStick: View {
        private static let base: CGFloat = 148
        private static let knob: CGFloat = 88
        private static let tapTravel: CGFloat = 12
        private static let doubleTap: TimeInterval = 0.35

        /// Which console stick the control drives.
        let stick: VirtualGamepad.Stick
        /// The stick button pressed by a quick double tap, or `nil` when tapping does nothing.
        var click: PlayStationControl?
        @State private var lastTap: TimeInterval = 0
        @Environment(\.virtualGamepad) private var gamepad

        private func ended(_ value: DragGesture.Value) {
            gamepad?.send(.released(stick))
            guard let click, hypot(value.translation.width, value.translation.height) < Self.tapTravel else {
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastTap < Self.doubleTap else {
                lastTap = now
                return
            }
            lastTap = 0
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            gamepad?.send(.pressed(click, down: true))
            Task { @MainActor [gamepad] in
                try? await Task.sleep(for: .milliseconds(120))
                gamepad?.send(.pressed(click, down: false))
            }
        }

        var body: some View {
            let state = gamepad?.pad.state ?? ControllerState()
            let travel = (Self.base - Self.knob) / 2
            let horizontal = stick == .left
                ? state.leftX
                : state.rightX
            let vertical = stick == .left
                ? state.leftY
                : state.rightY
            let moved = horizontal != 0 || vertical != 0
            ZStack {
                Color.clear
                    .glassEffect(AppGlass.control, in: .circle)
                Color.clear
                    .glassEffect(
                        moved
                            ? AppGlass.control.tint(.white.opacity(0.35))
                            : AppGlass.control.tint(.white.opacity(0.12)),
                        in: .circle
                    )
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(
                        x: CGFloat(horizontal) / CGFloat(Int16.max) * travel,
                        y: CGFloat(vertical) / CGFloat(Int16.max) * travel
                    )
            }
            .frame(width: Self.base, height: Self.base)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        gamepad?.send(.moved(
                            stick,
                            x: Double((value.location.x - Self.base / 2) / travel),
                            y: Double((value.location.y - Self.base / 2) / travel)
                        ))
                    }
                    .onEnded { value in
                        ended(value)
                    }
            )
            .accessibilityLabel(
                stick == .left
                    ? "Left stick"
                    : "Right stick"
            )
        }
    }
#endif
