/// What the Controls pane tells the user about the last thing they did.
public enum ControlsNotice: Equatable, Sendable {
    /// Nothing to say.
    case quiet

    /// A controller cannot get its own preset because the preset limit is reached.
    case presetLimit(Int)

    /// The configuration cannot be saved: an input is used twice in a preset, or a preset has no name.
    case invalidConfiguration

    /// The recorded keyboard shortcut does not use a modifier, or clashes with the app's own shortcuts.
    case shortcutNotAllowed

    /// The touchpad buttons are not two or three different buttons apart from the stream menu shortcut.
    case touchpadButtonsInvalid

    /// The stream menu buttons are not two to four different buttons apart from the touchpad shortcut.
    case streamMenuButtonsInvalid

    /// The connected controllers could not be read.
    case controllersUnreadable

    /// The controller did not accept the rumble test.
    case rumbleRejected

    /// The sentence shown for the notice, or `nil` when there is nothing to say.
    public var message: String? {
        switch self {
        case .quiet:
            nil
        case let .presetLimit(limit):
            "Delete a preset to change this controller’s buttons on their own; the limit is \(limit)."
        case .invalidConfiguration:
            "Use each input once per preset and give every preset a name. Changes are saved once they are valid."
        case .shortcutNotAllowed:
            "Use Command, Control or Option with a key the app does not already use."
        case .touchpadButtonsInvalid:
            "Choose two or three different buttons that don’t contain, or sit inside, the stream menu shortcut."
        case .streamMenuButtonsInvalid:
            "Choose two to four different buttons that don’t contain, or sit inside, the touchpad shortcut."
        case .controllersUnreadable:
            "Couldn’t read controllers. Check the connection and try again."
        case .rumbleRejected:
            "The controller did not accept the rumble test."
        }
    }
}
