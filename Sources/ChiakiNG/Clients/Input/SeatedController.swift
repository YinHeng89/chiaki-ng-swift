import ChiakiModels

/// A controller playing as one of players two to four.
struct SeatedController {
    /// The controller.
    let device: ControllerDevice

    /// The controller's preferences.
    var preferences: ControllerPreferences

    /// The fingers on the controller's own touchpad.
    var physicalTouchpad: PhysicalTouchpad
}
