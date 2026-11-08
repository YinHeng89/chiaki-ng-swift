import ChiakiClients
import ChiakiModels
import DesignSystem
import SwiftUI

/// Maps controller buttons and triggers to the SF Symbol and name printed on each controller family, so
/// on-screen prompts match the pad in the user's hands.
public enum ControllerGlyphs {
    /// Builds a resolver that turns prompt controls into glyphs for a controller family, or returns `nil`
    /// when no controller is connected so prompts fall back to keyboard hints.
    /// - Parameters:
    ///   - family: The family whose markings the glyphs should use.
    ///   - layout: Whether buttons are matched by position or by printed label.
    ///   - connected: Whether a controller is connected.
    /// - Returns: A glyph resolver, or `nil` when no controller is connected.
    public static func promptGlyphs(
        family: ControllerFamily,
        layout: ButtonLayout,
        connected: Bool
    ) -> ControllerGlyphResolver? {
        guard connected else {
            return nil
        }
        return ControllerGlyphResolver { control in
            prompt(control, family: family, layout: layout)
        }
    }

    /// The number of button codes the input layer reports, including touchpad and miscellaneous buttons.
    static let buttonCount = 26

    /// Returns the glyph for a logical button code on a controller family, after applying the button layout.
    ///
    /// D-pad buttons share glyphs across families; codes without a known glyph get a generic numbered name.
    /// - Parameters:
    ///   - logical: The logical button code.
    ///   - family: The controller family whose markings to use.
    ///   - layout: Whether buttons are matched by position or by printed label.
    static func button(_ logical: Int, family: ControllerFamily, layout: ButtonLayout = .position)
        -> ControllerGlyph {
        let code = layout.code(logical, family: family)
        if let glyph = common[code] {
            return glyph
        }
        let table: [Int: ControllerGlyph]
        switch family {
        case .playStation:
            table = playStation
        case .xbox:
            table = xbox
        case .nintendo:
            table = nintendo
        case .generic:
            table = generic
        }
        return table[code] ?? fallback(code)
    }

    private static func fallback(_ code: Int) -> ControllerGlyph {
        if (21...25).contains(code) {
            return ControllerGlyph(symbol: nil, name: .playbackGlyphsMisc(number: code - 19))
        }
        return ControllerGlyph(symbol: nil, name: .playbackGlyphsButton(number: code + 1))
    }

    /// Returns the glyph for a controller button on a controller family, after applying the button layout.
    /// - Parameters:
    ///   - button: The button to describe.
    ///   - family: The controller family whose markings to use.
    ///   - layout: Whether buttons are matched by position or by printed label.
    static func button(_ button: ControllerButton, family: ControllerFamily,
                       layout: ButtonLayout = .position) -> ControllerGlyph {
        self.button(button.rawValue, family: family, layout: layout)
    }

    /// Returns the glyph for a prompt control, which is either a button or one of the analog triggers.
    /// - Parameters:
    ///   - control: The control a prompt refers to.
    ///   - family: The controller family whose markings to use.
    ///   - layout: Whether buttons are matched by position or by printed label.
    static func prompt(_ control: ControllerPromptControl, family: ControllerFamily,
                       layout: ButtonLayout = .position) -> ControllerGlyph {
        switch control {
        case let .button(button):
            return self.button(button, family: family, layout: layout)
        case .leftTrigger:
            return leftTrigger(family: family)
        case .rightTrigger:
            return rightTrigger(family: family)
        }
    }

    /// Returns the left trigger glyph for a controller family, such as L2, LT or ZL.
    static func leftTrigger(family: ControllerFamily) -> ControllerGlyph {
        switch family {
        case .playStation:
            ControllerGlyph(symbol: "l2.button.roundedtop.horizontal", name: .playbackGlyphsL2)
        case .xbox:
            ControllerGlyph(symbol: "lt.button.roundedtop.horizontal", name: .playbackGlyphsLt)
        case .nintendo:
            ControllerGlyph(symbol: "zl.button.roundedtop.horizontal", name: .playbackGlyphsZl)
        case .generic:
            ControllerGlyph(symbol: nil, name: .playbackGlyphsLeftTrigger)
        }
    }

    /// Returns the right trigger glyph for a controller family, such as R2, RT or ZR.
    static func rightTrigger(family: ControllerFamily) -> ControllerGlyph {
        switch family {
        case .playStation:
            ControllerGlyph(symbol: "r2.button.roundedtop.horizontal", name: .playbackGlyphsR2)
        case .xbox:
            ControllerGlyph(symbol: "rt.button.roundedtop.horizontal", name: .playbackGlyphsRt)
        case .nintendo:
            ControllerGlyph(symbol: "zr.button.roundedtop.horizontal", name: .playbackGlyphsZr)
        case .generic:
            ControllerGlyph(symbol: nil, name: .playbackGlyphsRightTrigger)
        }
    }

    /// Returns the PlayStation glyph for a remote console control, used when describing the PlayStation input
    /// a mapping produces.
    static func action(_ control: PlayStationControl) -> ControllerGlyph {
        if let code = actionCodes[control] {
            return button(code, family: .playStation)
        }
        switch control {
        case .leftTrigger:
            return ControllerGlyph(symbol: "l2.button.roundedtop.horizontal", name: .playbackGlyphsL2)
        case .rightTrigger:
            return ControllerGlyph(symbol: "r2.button.roundedtop.horizontal", name: .playbackGlyphsR2)
        default:
            return ControllerGlyph(symbol: nil, name: control.label)
        }
    }

    private static let actionCodes: [PlayStationControl: Int] = [
        .cross: 0, .circle: 1, .square: 2, .triangle: 3, .share: 4, .system: 5, .options: 6,
        .leftStickButton: 7, .rightStickButton: 8, .leftShoulder: 9, .rightShoulder: 10,
        .dpadUp: 11, .down: 12, .left: 13, .right: 14, .touchpad: 20
    ]

    private static let common: [Int: ControllerGlyph] = [
        11: ControllerGlyph(symbol: "dpad.up.filled", name: .playbackGlyphsDpadUp),
        12: ControllerGlyph(symbol: "dpad.down.filled", name: .playbackGlyphsDpadDown),
        13: ControllerGlyph(symbol: "dpad.left.filled", name: .playbackGlyphsDpadLeft),
        14: ControllerGlyph(symbol: "dpad.right.filled", name: .playbackGlyphsDpadRight)
    ]

    private static let playStation: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "xmark.circle", name: .playbackGlyphsCross),
        1: ControllerGlyph(symbol: "circle.circle", name: .playbackGlyphsCircle),
        2: ControllerGlyph(symbol: "square.circle", name: .playbackGlyphsSquare),
        3: ControllerGlyph(symbol: "triangle.circle", name: .playbackGlyphsTriangle),
        4: ControllerGlyph(symbol: nil, name: .playbackGlyphsCreate),
        5: ControllerGlyph(symbol: "house.circle", name: .playbackGlyphsPs),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: .playbackGlyphsOptions),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: .playbackGlyphsL3),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: .playbackGlyphsR3),
        9: ControllerGlyph(symbol: "l1.button.roundedbottom.horizontal", name: .playbackGlyphsL1),
        10: ControllerGlyph(symbol: "r1.button.roundedbottom.horizontal", name: .playbackGlyphsR1),
        15: ControllerGlyph(symbol: "mic.circle", name: .playbackGlyphsMute),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: .playbackGlyphsRightBackButton),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: .playbackGlyphsLeftBackButton),
        18: ControllerGlyph(symbol: nil, name: .playbackGlyphsRightBackButton2),
        19: ControllerGlyph(symbol: nil, name: .playbackGlyphsLeftBackButton2),
        20: ControllerGlyph(symbol: nil, name: .playbackGlyphsTouchpad)
    ]

    private static let xbox: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "a.circle", name: .playbackGlyphsA),
        1: ControllerGlyph(symbol: "b.circle", name: .playbackGlyphsB),
        2: ControllerGlyph(symbol: "x.circle", name: .playbackGlyphsX),
        3: ControllerGlyph(symbol: "y.circle", name: .playbackGlyphsY),
        4: ControllerGlyph(symbol: "rectangle.on.rectangle.circle", name: .playbackGlyphsView),
        5: ControllerGlyph(symbol: "xbox.logo", name: .playbackGlyphsXbox),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: .playbackGlyphsMenu),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: .playbackGlyphsLs),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: .playbackGlyphsRs),
        9: ControllerGlyph(symbol: "lb.button.roundedbottom.horizontal", name: .playbackGlyphsLb),
        10: ControllerGlyph(symbol: "rb.button.roundedbottom.horizontal", name: .playbackGlyphsRb),
        15: ControllerGlyph(symbol: "square.and.arrow.up.circle", name: .playbackGlyphsShare),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: .playbackGlyphsP1),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: .playbackGlyphsP3),
        18: ControllerGlyph(symbol: nil, name: .playbackGlyphsP2),
        19: ControllerGlyph(symbol: nil, name: .playbackGlyphsP4),
        20: ControllerGlyph(symbol: nil, name: .playbackGlyphsTouchpad)
    ]

    private static let nintendo: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "b.circle", name: .playbackGlyphsB),
        1: ControllerGlyph(symbol: "a.circle", name: .playbackGlyphsA),
        2: ControllerGlyph(symbol: "y.circle", name: .playbackGlyphsY),
        3: ControllerGlyph(symbol: "x.circle", name: .playbackGlyphsX),
        4: ControllerGlyph(symbol: "minus.circle", name: .playbackGlyphsMinus),
        5: ControllerGlyph(symbol: "house.circle", name: .playbackGlyphsHome),
        6: ControllerGlyph(symbol: "plus.circle", name: .playbackGlyphsPlus),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: .playbackGlyphsLeftStick),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: .playbackGlyphsRightStick),
        9: ControllerGlyph(symbol: "l.button.roundedbottom.horizontal", name: .playbackGlyphsL),
        10: ControllerGlyph(symbol: "r.button.roundedbottom.horizontal", name: .playbackGlyphsR),
        15: ControllerGlyph(symbol: nil, name: .playbackGlyphsCapture)
    ]

    private static let generic: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "circle.grid.cross.down.filled", name: .playbackGlyphsSouth),
        1: ControllerGlyph(symbol: "circle.grid.cross.right.filled", name: .playbackGlyphsEast),
        2: ControllerGlyph(symbol: "circle.grid.cross.left.filled", name: .playbackGlyphsWest),
        3: ControllerGlyph(symbol: "circle.grid.cross.up.filled", name: .playbackGlyphsNorth),
        4: ControllerGlyph(symbol: nil, name: .playbackGlyphsBack),
        5: ControllerGlyph(symbol: nil, name: .playbackGlyphsGuide),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: .playbackGlyphsStart),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: .playbackGlyphsLeftStick),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: .playbackGlyphsRightStick),
        9: ControllerGlyph(symbol: nil, name: .playbackGlyphsLeftShoulder),
        10: ControllerGlyph(symbol: nil, name: .playbackGlyphsRightShoulder),
        15: ControllerGlyph(symbol: nil, name: .playbackGlyphsMisc(number: 1)),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: .playbackGlyphsRightPaddle1),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: .playbackGlyphsLeftPaddle1),
        18: ControllerGlyph(symbol: nil, name: .playbackGlyphsRightPaddle2),
        19: ControllerGlyph(symbol: nil, name: .playbackGlyphsLeftPaddle2),
        20: ControllerGlyph(symbol: nil, name: .playbackGlyphsTouchpad)
    ]
}

private struct ControllerFamilyKey: EnvironmentKey {
    static let defaultValue = ControllerFamily.playStation
}

private struct ControllerConnectedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ControllerButtonLayoutKey: EnvironmentKey {
    static let defaultValue = ButtonLayout.position
}

extension EnvironmentValues {
    /// The controller family whose markings prompts in this view should show.
    var controllerFamily: ControllerFamily {
        get {
            self[ControllerFamilyKey.self]
        }
        set {
            self[ControllerFamilyKey.self] = newValue
        }
    }
    /// Whether a controller is connected, which decides between controller and keyboard prompts.
    var controllerConnected: Bool {
        get {
            self[ControllerConnectedKey.self]
        }
        set {
            self[ControllerConnectedKey.self] = newValue
        }
    }
    /// Whether controller buttons in this view are matched by position or by printed label.
    var controllerButtonLayout: ButtonLayout {
        get {
            self[ControllerButtonLayoutKey.self]
        }
        set {
            self[ControllerButtonLayoutKey.self] = newValue
        }
    }
}

private struct NavigationControllerFamily: ViewModifier {
    let navigation: any ControllerNavigation
    @State private var family: ControllerFamily
    @State private var connected: Bool
    @State private var layout: ButtonLayout

    init(navigation: any ControllerNavigation) {
        self.navigation = navigation
        _family = State(initialValue: navigation.navigationFamily)
        _connected = State(initialValue: navigation.navigationConnected)
        _layout = State(initialValue: navigation.navigationButtonLayout)
    }

    private var promptGlyphs: ControllerGlyphResolver? {
        ControllerGlyphs.promptGlyphs(family: family, layout: layout, connected: connected)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.controllerFamily, family)
            .environment(\.controllerButtonLayout, layout)
            .environment(\.controllerConnected, connected)
            .environment(\.controllerPromptGlyphs, promptGlyphs)
            .onReceive(NotificationCenter.default.publisher(for: .controllerFamilyChanged)) { _ in
                family = navigation.navigationFamily
                layout = navigation.navigationButtonLayout
                connected = navigation.navigationConnected
            }
    }
}

extension View {
    /// Keeps the controller family, button layout, connection and prompt glyph environment values in step
    /// with the controller driving menu navigation.
    ///
    /// - Parameter navigation: The controller driving menu navigation.
    /// - Returns: The view with the controller environment values.
    public func navigationControllerFamily(_ navigation: any ControllerNavigation) -> some View {
        modifier(NavigationControllerFamily(navigation: navigation))
    }
}
