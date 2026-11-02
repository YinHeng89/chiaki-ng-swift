/// What a console does when the app launches.
public struct ConsoleLaunchOptions: Equatable, Sendable {
    /// Whether the app connects to this console at launch.
    public var connectAtLaunch: Bool

    /// Whether a login PIN is saved for the console.
    public var loginPINSaved: Bool

    /// Describes the options.
    ///
    /// - Parameters:
    ///   - connectAtLaunch: Whether to connect at launch.
    ///   - loginPINSaved: Whether a login PIN is saved.
    public init(connectAtLaunch: Bool = false, loginPINSaved: Bool = false) {
        self.connectAtLaunch = connectAtLaunch
        self.loginPINSaved = loginPINSaved
    }
}
