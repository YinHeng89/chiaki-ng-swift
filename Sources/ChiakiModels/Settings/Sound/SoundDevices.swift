/// The audio devices connected to this Mac, by name.
public struct SoundDevices: Equatable, Sendable {
    /// The output devices.
    public var outputs: [String]

    /// The input devices.
    public var inputs: [String]

    /// Creates a device list.
    ///
    /// - Parameters:
    ///   - outputs: The output devices.
    ///   - inputs: The input devices.
    public init(outputs: [String] = [], inputs: [String] = []) {
        self.outputs = outputs
        self.inputs = inputs
    }

    /// The choices a picker offers: the connected devices, plus the selected one when it is not connected.
    ///
    /// - Parameters:
    ///   - connected: The connected devices.
    ///   - selected: The saved device, or `nil` for the system default.
    /// - Returns: The names to offer.
    public static func choices(_ connected: [String], selected: String?) -> [String] {
        guard let selected, !connected.contains(selected) else {
            return connected
        }
        return connected + [selected]
    }
}
