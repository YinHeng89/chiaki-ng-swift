/// What a PS5 cloud service is told about the client's own screen.
///
/// A stream nobody can play wins over the menu that covers it: a sleeping display or a locked screen is
/// ``background`` even while the stream menu is open, the same as a screen that is switched off. A minimised or
/// hidden app is ``background`` too unless background controller input is on, because without it the controller
/// no longer reaches the stream; with it on the game keeps playing, since the cloud plays the console's menu
/// music in place of the game's while in the background.
public enum CloudSystemUIState: Equatable, Sendable {
    /// The stream is on screen and nothing of the app's covers it.
    case game

    /// The stream menu covers the stream.
    case overlaid

    /// Nobody can play the stream: the screen is off, or the app is minimised or hidden, or on iOS in the
    /// background, without background controller input.
    case background

    /// Picks the state for what the app shows.
    ///
    /// - Parameters:
    ///   - menuCoversStream: Whether the stream menu is open over the stream.
    ///   - screenOn: Whether the displays are awake and the screen is unlocked.
    ///   - appHidden: Whether the stream's window is minimised or the app is hidden, or on iOS whether the app is
    ///     in the background, which keeps the stream running.
    ///   - backgroundInput: Whether the controller keeps reaching the stream while the app is not active.
    public init(menuCoversStream: Bool, screenOn: Bool, appHidden: Bool, backgroundInput: Bool) {
        if !screenOn || appHidden && !backgroundInput {
            self = .background
        } else if menuCoversStream {
            self = .overlaid
        } else {
            self = .game
        }
    }
}
