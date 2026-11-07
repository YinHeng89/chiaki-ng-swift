import Foundation

/// What a guest is told about the host an invitation claims to come from.
public enum KakusanHostClaim {
    /// The explanation shown under the host's claimed name.
    ///
    /// - Parameter name: The remembered name the invitation's hint matches, if any.
    /// - Returns: The explanation.
    public static func text(knownAs name: String?) -> LocalizedStringResource {
        name == nil
            ? .kakusanHostClaimUnknown
            : .kakusanHostClaimKnown
    }
}
