import ChiakiModels
import ComposableArchitecture
import SwiftUI

#if os(iOS)
    /// The compact on-screen DualSense layout for smaller iOS screens: sticks and face buttons stay visible,
    /// while triggers, shoulders, the D-pad and system buttons fade until the screen is tapped.
    ///
    /// The four clusters sit at fractions of the width, so a narrow screen such as half an iPad keeps the
    /// D-pad clear of the right stick.
    struct VirtualGamepadCompactView: View {
        /// The touchpad shown in the middle of the screen when the user reveals it, or `nil` when there is no
        /// virtual touchpad.
        let touchpad: VirtualTouchpadModel?
        @Environment(\.virtualGamepad) private var gamepad

        /// Where the outer clusters, the left stick and the face buttons, sit as a fraction of the width.
        static let outerClusterFraction: CGFloat = 0.17
        /// Where the inner clusters, the D-pad and the right stick, sit as a fraction of the width.
        static let innerClusterFraction: CGFloat = 0.36
        /// How much of the width the revealed touchpad takes.
        static let surfaceWidthFraction: CGFloat = 0.425

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let lit = gamepad?.secondary == .lit
                let left = CGPoint(x: size.width * Self.outerClusterFraction, y: size.height - 150)
                let right = CGPoint(
                    x: size.width * (1 - Self.outerClusterFraction), y: size.height - 170
                )
                let innerLeft = size.width * Self.innerClusterFraction
                let innerRight = size.width * (1 - Self.innerClusterFraction)
                ZStack {
                    Color.clear
                        .contentShape(.rect)
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { tap in
                                    gamepad?.send(.secondaryRevealed)
                                    if surfaceFrame(in: size).contains(tap.location) {
                                        touchpad?.reveal()
                                    }
                                }
                        )
                    if let touchpad, touchpad.pad.isShown {
                        surface(touchpad, in: size)
                    }
                    Group {
                        VirtualArcButton(
                            control: .leftTrigger,
                            text: "L2",
                            radius: 166,
                            from: -110,
                            until: -30
                        )
                        .position(left)
                        VirtualArcButton(
                            control: .leftShoulder,
                            text: "L1",
                            radius: 118,
                            from: -110,
                            until: -30
                        )
                        .position(left)
                        VirtualArcButton(
                            control: .rightTrigger,
                            text: "R2",
                            radius: 172,
                            from: -150,
                            until: -70
                        )
                        .position(right)
                        VirtualArcButton(
                            control: .rightShoulder,
                            text: "R1",
                            radius: 124,
                            from: -150,
                            until: -70
                        )
                        .position(right)
                        directions(at: CGPoint(x: innerLeft, y: size.height - 105))
                        system(in: size)
                    }
                    .virtualSecondary(lit: lit)
                    VirtualStick(stick: .left, click: .leftStickButton)
                        .position(left)
                    VirtualStick(stick: .right, click: .rightStickButton)
                        .position(x: innerRight, y: size.height - 105)
                    actions(at: right)
                }
            }
        }

        private func surfaceFrame(in size: CGSize) -> CGRect {
            let width = max(200, size.width * Self.surfaceWidthFraction)
            let height = max(120, size.height - 370)
            return CGRect(x: (size.width - width) / 2, y: 70, width: width, height: height)
        }

        private func surface(_ model: VirtualTouchpadModel, in size: CGSize) -> some View {
            let frame = surfaceFrame(in: size)
            return HStack(spacing: 4) {
                VirtualTouchpadView(model: model, side: .left)
                VirtualTouchpadView(model: model, side: .right)
            }
            .frame(width: frame.width, height: frame.height)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .position(x: frame.midX, y: frame.midY)
        }

        private func system(in size: CGSize) -> some View {
            let middle = size.width / 2
            return ZStack {
                VirtualPadButton(
                    control: .share, symbol: "square.and.arrow.up", shape: .capsule, width: 64, height: 40
                )
                .position(x: middle - 114, y: 34)
                VirtualPadButton(
                    control: .system, symbol: "playstation.logo", shape: .capsule, width: 64, height: 40
                )
                .position(x: middle - 38, y: 34)
                VirtualPadButton(
                    control: .options, symbol: "line.3.horizontal", shape: .capsule, width: 64, height: 40
                )
                .position(x: middle + 38, y: 34)
                VirtualMenuButton()
                    .scaleEffect(1.4)
                    .position(x: middle + 114, y: 34)
            }
        }

        private func directions(at centre: CGPoint) -> some View {
            let reach: CGFloat = 44
            return ZStack {
                VirtualPadButton(control: .dpadUp, shape: .direction(.up), width: 48, height: 56)
                    .position(x: centre.x, y: centre.y - reach)
                VirtualPadButton(control: .down, shape: .direction(.down), width: 48, height: 56)
                    .position(x: centre.x, y: centre.y + reach)
                VirtualPadButton(control: .left, shape: .direction(.left), width: 56, height: 48)
                    .position(x: centre.x - reach, y: centre.y)
                VirtualPadButton(control: .right, shape: .direction(.right), width: 56, height: 48)
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

    /// A trigger or shoulder button drawn as a curved band around a stick, with its label placed at the
    /// middle of the arc.
    struct VirtualArcButton: View {
        /// The console control the button presses.
        let control: PlayStationControl
        /// The label drawn on the arc, such as L2 or R1.
        let text: String
        /// The distance from the arc's centre to the middle of the band.
        let radius: CGFloat
        /// The angle in degrees where the arc starts.
        let from: Double
        /// The angle in degrees where the arc ends.
        let until: Double

        var body: some View {
            let side = (radius + VirtualPadShape.arcWidth) * 2
            let middle = (from + until) / 2 * .pi / 180
            ZStack {
                VirtualPadButton(
                    control: control,
                    shape: .arc(radius: radius, from: from, until: until),
                    width: side,
                    height: side
                )
                Text(text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(
                        x: side / 2 + radius * CGFloat(cos(middle)),
                        y: side / 2 + radius * CGFloat(sin(middle))
                    )
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
        }
    }

    extension View {
        /// Fades secondary on-screen controls almost to invisible unless `lit`, animating the change.
        func virtualSecondary(lit: Bool) -> some View {
            opacity(
                lit
                    ? 1
                    : 0.02
            )
            .animation(.easeOut(duration: 0.25), value: lit)
        }
    }
#endif
