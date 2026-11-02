import SwiftUI

/// SF Symbol names for the icons the app reuses across screens, keyed by the action or place they stand for.
public enum AppIcon: String, Sendable {
    /// Two people, shown on the control that switches between saved accounts.
    case switchAccount = "person.2"
    /// A person with a plus badge, shown on the control that adds an account.
    case addAccount = "person.badge.plus"
    /// A circular arrow, shown on the control that reloads account details.
    case refreshDetails = "arrow.clockwise"
    /// A person with a key badge, shown on the control that signs in to PlayStation Network.
    case signIn = "person.badge.key"
    /// A trash can, shown on the control that removes an account.
    case deleteAccount = "trash"
    /// A gear, shown on the control that opens settings.
    case settings = "gearshape"
    /// A cross, shown on controls that close a panel or sheet.
    case close = "xmark"
    /// A right chevron, shown on rows that expand or drill into more detail.
    case expand = "chevron.right"
    /// Left-aligned text lines, shown on the live developer log toggle.
    case logging = "text.alignleft"
    /// A folder, shown on controls that reveal a location on disk.
    case folder = "folder"
    /// A plus, shown on controls that add an item.
    case add = "plus"
    /// A checkmark, marking the currently selected option.
    case selected = "checkmark"
    /// A filled play triangle, shown on controls that start a stream.
    case start = "play.fill"
    /// A pencil, shown on controls that edit an item.
    case edit = "pencil"
    /// An up-right arrow, shown on controls that open something outside the current view.
    case open = "arrow.up.right"
    /// A game controller, standing for a console.
    case console = "gamecontroller"
    /// Books on a shelf, standing for the game library.
    case library = "books.vertical"
    /// A shopping bag, standing for the store.
    case store = "bag"
    /// A cloud, standing for cloud streaming.
    case cloud = "cloud"
    /// A trophy, standing for the account's PlayStation trophies.
    case trophy = "trophy"
    /// A clock, marking a game that has not been released yet.
    case release = "clock"
    /// An hourglass, marking a game held only as a trial.
    case trial = "hourglass"
    /// A play symbol in a square, marking a game held only as a demo, an ordinary trial with no time limit.
    case demo = "play.square"
    /// An outlined iCloud glyph, marking a cloud game whose availability is not yet confirmed.
    case cloudUnconfirmed = "icloud"
    /// A struck-through cloud, marking a cloud game that cannot be streamed.
    case cloudUnavailable = "icloud.slash"
    /// A power symbol, shown on the control that quits the app.
    case quit = "power"

    /// The icon used for subscription offers, which shares the plus glyph of ``AppIcon/add``.
    public static var subscription: Self {
        .add
    }

    /// A SwiftUI image drawn from the symbol named by the raw value.
    public var image: Image {
        Image(systemName: rawValue)
    }
}
