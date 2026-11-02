/// One input bound to one console control.
public struct InputBinding: Codable, Equatable, Sendable {
    /// The kind of input.
    public var source: InputSource

    /// The key, mouse or gamepad button code.
    public var code: Int

    /// The label shown for the input, such as a key name.
    public var label: String

    /// The console control it drives.
    public var target: PlayStationControl

    /// Creates a binding.
    ///
    /// - Parameters:
    ///   - source: The kind of input.
    ///   - code: The input code.
    ///   - label: The label shown for it.
    ///   - target: The control it drives.
    public init(source: InputSource, code: Int, label: String, target: PlayStationControl) {
        self.source = source
        self.code = code
        self.label = label
        self.target = target
    }
}

/// The kind of physical input a binding listens to.
public enum InputSource: String, Codable, Sendable, CaseIterable {
    /// A Mac keyboard key, by virtual key code.
    case macKey

    /// A mouse button, by button number.
    case mouseButton

    /// A gamepad button, by the input layer's button index.
    case gamepadButton
}
