/// What a guest knows about the host.
public enum KakusanGuestHost: Equatable, Sendable {
    /// Nothing yet.
    case unknown

    /// The name the invitation claims, unverified.
    case claimed(name: String?)

    /// The host's verified identity.
    case proven(KakusanIdentity)
}
