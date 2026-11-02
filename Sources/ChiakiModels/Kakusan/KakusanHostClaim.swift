/// What a guest is told about the host an invitation claims to come from.
public enum KakusanHostClaim {
    /// The explanation shown under the host's claimed name.
    ///
    /// - Parameter name: The remembered name the invitation's hint matches, if any.
    /// - Returns: The explanation.
    public static func text(knownAs name: String?) -> String {
        name == nil
            ? "You’ll see this device’s fingerprint once you’re connected"
            : "This looks like a device you’ve played with. That’s confirmed once you’re connected"
    }
}
