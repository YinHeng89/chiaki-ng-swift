import ChiakiAssets
import ChiakiModels
import CoreGraphics
import Foundation
import PlatformUI

/// A controller drawing for the Controls pane and where each of its buttons sits on it.
///
/// Positions are fractions of the image's width and height, keyed by SDL gamepad button code, so a binding's
/// code finds its button whatever size the drawing is shown at. PlayStation controllers without adaptive
/// triggers use the DualShock 4 drawing, and generic controllers a drawing with the standard gamepad layout
/// and no maker's branding.
struct ControllerArtwork: Equatable, Sendable {
    /// The image's resource name in `ChiakiAssets`.
    let resource: String

    /// The image's width divided by its height.
    let aspectRatio: CGFloat

    /// Where each button sits, by SDL gamepad button code.
    let buttons: [Int: CGPoint]

    /// Where the left trigger sits.
    let leftTrigger: CGPoint

    /// Where the right trigger sits.
    let rightTrigger: CGPoint

    /// The drawing for a controller.
    ///
    /// - Parameter device: The controller, or `nil` for the console's own DualSense.
    /// - Returns: The DualSense, DualShock 4, Xbox, Pro Controller or generic drawing.
    static func of(_ device: ControllerDevice?) -> Self {
        guard let device else {
            return dualSense
        }
        switch device.family {
        case .playStation:
            return device.adaptiveTriggers
                ? dualSense
                : dualShock4
        case .nintendo:
            return proController
        case .xbox:
            return xbox
        case .generic:
            return generic
        }
    }

    /// The DualSense drawing.
    static let dualSense = Self(
        resource: "binding-dualsense",
        aspectRatio: 1200 / 804,
        buttons: [
            0: CGPoint(x: 0.809, y: 0.407), 1: CGPoint(x: 0.884, y: 0.296), 2: CGPoint(x: 0.735, y: 0.296),
            3: CGPoint(x: 0.809, y: 0.186), 4: CGPoint(x: 0.264, y: 0.128), 5: CGPoint(x: 0.495, y: 0.495),
            6: CGPoint(x: 0.733, y: 0.120), 7: CGPoint(x: 0.337, y: 0.500), 8: CGPoint(x: 0.661, y: 0.500),
            9: CGPoint(x: 0.238, y: 0.067), 10: CGPoint(x: 0.761, y: 0.067), 11: CGPoint(x: 0.186, y: 0.212),
            12: CGPoint(x: 0.186, y: 0.376), 13: CGPoint(x: 0.130, y: 0.295), 14: CGPoint(x: 0.243, y: 0.295),
            15: CGPoint(x: 0.499, y: 0.580), 20: CGPoint(x: 0.499, y: 0.189)
        ],
        leftTrigger: CGPoint(x: 0.171, y: 0.033),
        rightTrigger: CGPoint(x: 0.828, y: 0.033)
    )

    /// The DualShock 4 drawing.
    static let dualShock4 = Self(
        resource: "binding-dualshock4",
        aspectRatio: 1200 / 758,
        buttons: [
            0: CGPoint(x: 0.802, y: 0.402), 1: CGPoint(x: 0.875, y: 0.288), 2: CGPoint(x: 0.732, y: 0.288),
            3: CGPoint(x: 0.802, y: 0.178), 4: CGPoint(x: 0.305, y: 0.136), 5: CGPoint(x: 0.498, y: 0.505),
            6: CGPoint(x: 0.697, y: 0.136), 7: CGPoint(x: 0.338, y: 0.488), 8: CGPoint(x: 0.653, y: 0.488),
            9: CGPoint(x: 0.217, y: 0.055), 10: CGPoint(x: 0.783, y: 0.055), 11: CGPoint(x: 0.200, y: 0.211),
            12: CGPoint(x: 0.200, y: 0.372), 13: CGPoint(x: 0.150, y: 0.290), 14: CGPoint(x: 0.250, y: 0.290),
            20: CGPoint(x: 0.500, y: 0.198)
        ],
        leftTrigger: CGPoint(x: 0.125, y: 0.029),
        rightTrigger: CGPoint(x: 0.875, y: 0.029)
    )

    /// The Xbox drawing.
    static let xbox = Self(
        resource: "binding-xbox",
        aspectRatio: 1200 / 845,
        buttons: [
            0: CGPoint(x: 0.747, y: 0.376), 1: CGPoint(x: 0.813, y: 0.285), 2: CGPoint(x: 0.683, y: 0.285),
            3: CGPoint(x: 0.747, y: 0.193), 4: CGPoint(x: 0.428, y: 0.281), 5: CGPoint(x: 0.500, y: 0.144),
            6: CGPoint(x: 0.569, y: 0.281), 7: CGPoint(x: 0.249, y: 0.288), 8: CGPoint(x: 0.627, y: 0.494),
            9: CGPoint(x: 0.292, y: 0.054), 10: CGPoint(x: 0.707, y: 0.054), 11: CGPoint(x: 0.370, y: 0.439),
            12: CGPoint(x: 0.370, y: 0.581), 13: CGPoint(x: 0.321, y: 0.509), 14: CGPoint(x: 0.419, y: 0.509),
            15: CGPoint(x: 0.499, y: 0.358)
        ],
        leftTrigger: CGPoint(x: 0.223, y: 0.066),
        rightTrigger: CGPoint(x: 0.777, y: 0.066)
    )

    /// The generic drawing: the Xbox outline without its maker's button.
    static let generic = Self(
        resource: "binding-generic",
        aspectRatio: xbox.aspectRatio,
        buttons: xbox.buttons.filter { $0.key != 5 },
        leftTrigger: xbox.leftTrigger,
        rightTrigger: xbox.rightTrigger
    )

    /// The Pro Controller drawing.
    static let proController = Self(
        resource: "binding-pro-controller",
        aspectRatio: 1200 / 841,
        buttons: [
            0: CGPoint(x: 0.755, y: 0.403), 1: CGPoint(x: 0.832, y: 0.310), 2: CGPoint(x: 0.682, y: 0.310),
            3: CGPoint(x: 0.755, y: 0.217), 4: CGPoint(x: 0.381, y: 0.206), 5: CGPoint(x: 0.570, y: 0.310),
            6: CGPoint(x: 0.620, y: 0.206), 7: CGPoint(x: 0.235, y: 0.310), 8: CGPoint(x: 0.628, y: 0.494),
            9: CGPoint(x: 0.177, y: 0.087), 10: CGPoint(x: 0.824, y: 0.087), 11: CGPoint(x: 0.352, y: 0.430),
            12: CGPoint(x: 0.352, y: 0.568), 13: CGPoint(x: 0.302, y: 0.498), 14: CGPoint(x: 0.401, y: 0.498),
            15: CGPoint(x: 0.431, y: 0.310)
        ],
        leftTrigger: CGPoint(x: 0.258, y: 0.030),
        rightTrigger: CGPoint(x: 0.743, y: 0.030)
    )

    /// The standard gamepad button of each console control on a DualSense, used to place keyboard bindings
    /// on the console's own controller.
    static let consoleButtons: [PlayStationControl: Int] = [
        .cross: 0, .circle: 1, .square: 2, .triangle: 3, .share: 4, .system: 5, .options: 6,
        .leftStickButton: 7, .rightStickButton: 8, .leftShoulder: 9, .rightShoulder: 10,
        .dpadUp: 11, .down: 12, .left: 13, .right: 14, .touchpad: 20
    ]

    /// Where a control sits when its button is the controller's own: the button bound to it, or the trigger
    /// that drives it without a binding.
    ///
    /// - Parameters:
    ///   - control: The console control.
    ///   - code: The SDL button code bound to it, or `nil` when no button is.
    ///   - family: The controller's family.
    ///   - layout: The controller's button layout.
    /// - Returns: The position, or `nil` when the control has no place on the drawing.
    func position(of control: PlayStationControl, code: Int?, family: ControllerFamily,
                  layout: ButtonLayout) -> CGPoint? {
        if let code {
            return buttons[layout.code(code, family: family)]
        }
        switch control {
        case .leftTrigger:
            return leftTrigger
        case .rightTrigger:
            return rightTrigger
        default:
            return nil
        }
    }

    /// Where a control sits on the console's own controller.
    ///
    /// - Parameter control: The console control.
    /// - Returns: The position, or `nil` for controls that are not buttons, such as stick directions.
    func consolePosition(of control: PlayStationControl) -> CGPoint? {
        if let code = Self.consoleButtons[control] {
            return buttons[code]
        }
        return position(of: control, code: nil, family: .playStation, layout: .position)
    }

    /// The drawing's image, loaded once per drawing.
    var image: PlatformImage? {
        Self.images[resource]
    }

    private static let images: [String: PlatformImage] = Dictionary(
        uniqueKeysWithValues: [dualSense, dualShock4, xbox, generic, proController].compactMap { artwork in
            ChiakiAssets.url(forResource: artwork.resource, withExtension: "png")
                .flatMap { PlatformImage(contentsOf: $0) }
                .map { (artwork.resource, $0) }
        }
    )
}
