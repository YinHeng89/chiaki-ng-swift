/// An account added by id only, as the core saves and restores it.
public struct StoredHomeUser: Hashable, Sendable {
    /// The PSN account id.
    public let account: AccountID

    /// The display name.
    public let name: String

    /// Describes a home user.
    ///
    /// - Parameters:
    ///   - account: The PSN account id.
    ///   - name: The display name.
    public init(account: AccountID, name: String) {
        self.account = account
        self.name = name
    }
}
