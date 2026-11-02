/// A code the console asks for before it lets a player in.
public enum StreamAccessPrompt: Hashable, Sendable {
    /// The console's login PIN, asked again when `retry` is set because the last one was wrong.
    case loginPIN(retry: Bool)

    /// The passcode of the account joining on a couch pad, asked again when `retry` is set.
    case controllerPasscode(pad: UInt8, retry: Bool)

    /// The couch pad the prompt is for, when it is a controller passcode.
    public var pad: UInt8? {
        if case .controllerPasscode(let pad, _) = self {
            return pad
        }
        return nil
    }

    /// Whether the prompt is the console's login PIN.
    public var isLoginPIN: Bool {
        if case .loginPIN = self {
            return true
        }
        return false
    }
}
