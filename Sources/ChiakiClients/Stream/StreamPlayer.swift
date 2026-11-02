import ChiakiModels

/// The native video player one live stream session drives.
///
/// The app's player conforms by translating its main-queue handlers into ``PlayerSignal``s, so the session,
/// its `PlayerEventRelay` and their tests never see the native type.
@MainActor
public protocol StreamPlayer: AnyObject, Sendable {
    /// The view the player renders into.
    var surface: StreamSurface { get }

    /// Whether the console refused the last rest mode request.
    var restRefused: Bool { get }

    /// Starts delivering the player's handlers, in the order they fire, to `receive`.
    ///
    /// - Parameter receive: Called on the main actor for each signal.
    func connect(_ receive: @escaping @MainActor (PlayerSignal) -> Void)

    /// Stops delivering signals and drops every handler.
    func disconnect()

    /// Ends the stream.
    func stop()

    /// Ends the stream and asks the console to enter rest mode.
    func stopWithRest()

    /// Ends the stream because the computer is going to sleep.
    func stopForSleep()

    /// Ends the stream for sleep and asks the console to enter rest mode.
    func stopForSleepWithRest()

    /// Sends the console's login PIN.
    ///
    /// - Parameter code: The PIN.
    /// - Returns: Whether the console accepted it.
    func submitLoginPIN(_ code: StreamAccessCode) async -> Bool

    /// Sends the passcode of the account joining on a couch pad.
    ///
    /// - Parameters:
    ///   - code: The passcode.
    ///   - pad: The pad.
    /// - Returns: Whether it was sent.
    func submitControllerPasscode(_ code: StreamAccessCode, pad: UInt8) -> Bool

    /// Asks the console to show its home screen.
    ///
    /// - Returns: Whether the request was sent.
    func goHome() -> Bool

    /// Sends a change to the console's on-screen keyboard.
    ///
    /// - Parameter command: The change.
    /// - Returns: Whether it was sent.
    func send(_ command: ConsoleKeyboardCommand) -> Bool

    /// Chooses an offered cloud datacenter.
    ///
    /// - Parameter name: The datacenter's name.
    /// - Returns: Whether the core took the choice.
    func selectDatacenter(_ name: String) -> Bool

    /// Applies picture and sound settings the stream menu changed.
    ///
    /// - Parameter tuning: The settings.
    func apply(_ tuning: StreamTuningConfiguration)
}

/// Something a ``StreamPlayer`` reported through one of its handlers.
public enum PlayerSignal: Equatable, Sendable {
    /// Something the session reports to its feature.
    case event(StreamSessionEvent)

    /// The game set a pad's light colour; only the session's input reacts to it.
    case gameLight(pad: UInt8, color: UInt32)
}
