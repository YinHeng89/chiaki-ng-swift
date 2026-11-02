/// A remote player as the couch sees them: the shared session's guest and the name they are known by.
public struct KakusanRemotePlayer: Equatable, Sendable {
    /// The guest's id in the shared session.
    public let guest: KakusanGuestID

    /// The remembered name, if the device is known.
    public let name: String?

    /// Creates a remote player.
    ///
    /// - Parameters:
    ///   - guest: The guest's id.
    ///   - name: The remembered name.
    public init(guest: KakusanGuestID, name: String?) {
        self.guest = guest
        self.name = name
    }
}
