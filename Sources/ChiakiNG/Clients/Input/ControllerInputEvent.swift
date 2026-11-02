import CInput

/// The kinds of native controller event the input stack tells apart.
enum ControllerInputEvent {
    /// A button changed.
    static let button = Int32(NX_INPUT_EVENT_BUTTON)
    /// An axis moved.
    static let axis = Int32(NX_INPUT_EVENT_AXIS)
    /// A controller was disconnected.
    static let removed = Int32(NX_INPUT_EVENT_REMOVED)
    /// A controller was connected.
    static let added = Int32(NX_INPUT_EVENT_ADDED)
    /// A motion sensor reported.
    static let sensor = Int32(NX_INPUT_EVENT_SENSOR)
    /// A finger touched the touchpad.
    static let touchDown = Int32(NX_INPUT_EVENT_TOUCH_DOWN)
    /// A finger moved on the touchpad.
    static let touchMotion = Int32(NX_INPUT_EVENT_TOUCH_MOTION)
    /// A finger left the touchpad.
    static let touchUp = Int32(NX_INPUT_EVENT_TOUCH_UP)
    /// The adaptive trigger states changed.
    static let triggerState = Int32(NX_INPUT_EVENT_TRIGGER_STATE)

    /// Whether an event is a motion sensor sample.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` for sensor events.
    static func isSensor(_ event: nx_input_event) -> Bool {
        event.kind == sensor
    }

    /// Whether an event is a touchpad contact.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` for touch down, motion and up.
    static func isTouch(_ event: nx_input_event) -> Bool {
        switch event.kind {
        case touchDown, touchMotion, touchUp:
            true
        default:
            false
        }
    }
}
