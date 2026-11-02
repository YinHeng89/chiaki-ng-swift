/// What a Kakusan guest joins with.
public struct KakusanGuestConfiguration: Equatable, Sendable {
    /// The host's invitation.
    public let invitation: KakusanBlock

    /// Creates a configuration.
    ///
    /// - Parameter invitation: The invitation.
    public init(invitation: KakusanBlock) {
        self.invitation = invitation
    }
}
