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
            return ControllerGlyph(symbol: nil, name: "Misc \(code - 19)")
        }
        return ControllerGlyph(symbol: nil, name: "Button \(code + 1)")
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
            ControllerGlyph(symbol: "l2.button.roundedtop.horizontal", name: "L2")
        case .xbox:
            ControllerGlyph(symbol: "lt.button.roundedtop.horizontal", name: "LT")
        case .nintendo:
            ControllerGlyph(symbol: "zl.button.roundedtop.horizontal", name: "ZL")
        case .generic:
            ControllerGlyph(symbol: nil, name: "Left trigger")
        }
    }

    /// Returns the right trigger glyph for a controller family, such as R2, RT or ZR.
    static func rightTrigger(family: ControllerFamily) -> ControllerGlyph {
        switch family {
        case .playStation:
            ControllerGlyph(symbol: "r2.button.roundedtop.horizontal", name: "R2")
        case .xbox:
            ControllerGlyph(symbol: "rt.button.roundedtop.horizontal", name: "RT")
        case .nintendo:
            ControllerGlyph(symbol: "zr.button.roundedtop.horizontal", name: "ZR")
        case .generic:
            ControllerGlyph(symbol: nil, name: "Right trigger")
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
            return ControllerGlyph(symbol: "l2.button.roundedtop.horizontal", name: "L2")
        case .rightTrigger:
            return ControllerGlyph(symbol: "r2.button.roundedtop.horizontal", name: "R2")
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
        11: ControllerGlyph(symbol: "dpad.up.filled", name: "D-pad up"),
        12: ControllerGlyph(symbol: "dpad.down.filled", name: "D-pad down"),
        13: ControllerGlyph(symbol: "dpad.left.filled", name: "D-pad left"),
        14: ControllerGlyph(symbol: "dpad.right.filled", name: "D-pad right")
    ]

    private static let playStation: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "xmark.circle", name: "Cross"),
        1: ControllerGlyph(symbol: "circle.circle", name: "Circle"),
        2: ControllerGlyph(symbol: "square.circle", name: "Square"),
        3: ControllerGlyph(symbol: "triangle.circle", name: "Triangle"),
        4: ControllerGlyph(symbol: nil, name: "Create"),
        5: ControllerGlyph(symbol: "house.circle", name: "PS"),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: "Options"),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: "L3"),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: "R3"),
        9: ControllerGlyph(symbol: "l1.button.roundedbottom.horizontal", name: "L1"),
        10: ControllerGlyph(symbol: "r1.button.roundedbottom.horizontal", name: "R1"),
        15: ControllerGlyph(symbol: "mic.circle", name: "Mute"),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: "Right back button"),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: "Left back button"),
        18: ControllerGlyph(symbol: nil, name: "Right back button 2"),
        19: ControllerGlyph(symbol: nil, name: "Left back button 2"),
        20: ControllerGlyph(symbol: nil, name: "Touchpad")
    ]

    private static let xbox: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "a.circle", name: "A"),
        1: ControllerGlyph(symbol: "b.circle", name: "B"),
        2: ControllerGlyph(symbol: "x.circle", name: "X"),
        3: ControllerGlyph(symbol: "y.circle", name: "Y"),
        4: ControllerGlyph(symbol: "rectangle.on.rectangle.circle", name: "View"),
        5: ControllerGlyph(symbol: "xbox.logo", name: "Xbox"),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: "Menu"),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: "LS"),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: "RS"),
        9: ControllerGlyph(symbol: "lb.button.roundedbottom.horizontal", name: "LB"),
        10: ControllerGlyph(symbol: "rb.button.roundedbottom.horizontal", name: "RB"),
        15: ControllerGlyph(symbol: "square.and.arrow.up.circle", name: "Share"),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: "P1"),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: "P3"),
        18: ControllerGlyph(symbol: nil, name: "P2"),
        19: ControllerGlyph(symbol: nil, name: "P4"),
        20: ControllerGlyph(symbol: nil, name: "Touchpad")
    ]

    private static let nintendo: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "b.circle", name: "B"),
        1: ControllerGlyph(symbol: "a.circle", name: "A"),
        2: ControllerGlyph(symbol: "y.circle", name: "Y"),
        3: ControllerGlyph(symbol: "x.circle", name: "X"),
        4: ControllerGlyph(symbol: "minus.circle", name: "Minus"),
        5: ControllerGlyph(symbol: "house.circle", name: "Home"),
        6: ControllerGlyph(symbol: "plus.circle", name: "Plus"),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: "Left stick"),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: "Right stick"),
        9: ControllerGlyph(symbol: "l.button.roundedbottom.horizontal", name: "L"),
        10: ControllerGlyph(symbol: "r.button.roundedbottom.horizontal", name: "R"),
        15: ControllerGlyph(symbol: nil, name: "Capture")
    ]

    private static let generic: [Int: ControllerGlyph] = [
        0: ControllerGlyph(symbol: "circle.grid.cross.down.filled", name: "South"),
        1: ControllerGlyph(symbol: "circle.grid.cross.right.filled", name: "East"),
        2: ControllerGlyph(symbol: "circle.grid.cross.left.filled", name: "West"),
        3: ControllerGlyph(symbol: "circle.grid.cross.up.filled", name: "North"),
        4: ControllerGlyph(symbol: nil, name: "Back"),
        5: ControllerGlyph(symbol: nil, name: "Guide"),
        6: ControllerGlyph(symbol: "line.3.horizontal.circle", name: "Start"),
        7: ControllerGlyph(symbol: "l.joystick.press.down", name: "Left stick"),
        8: ControllerGlyph(symbol: "r.joystick.press.down", name: "Right stick"),
        9: ControllerGlyph(symbol: nil, name: "Left shoulder"),
        10: ControllerGlyph(symbol: nil, name: "Right shoulder"),
        15: ControllerGlyph(symbol: nil, name: "Misc 1"),
        16: ControllerGlyph(symbol: "paddleshifter.right", name: "Right paddle 1"),
        17: ControllerGlyph(symbol: "paddleshifter.left", name: "Left paddle 1"),
        18: ControllerGlyph(symbol: nil, name: "Right paddle 2"),
        19: ControllerGlyph(symbol: nil, name: "Left paddle 2"),
        20: ControllerGlyph(symbol: nil, name: "Touchpad")
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
