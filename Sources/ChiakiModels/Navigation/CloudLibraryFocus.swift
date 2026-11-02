/// A controller focus stop in the cloud library: a game card, a header control, the page bar or a control of
/// the open game's detail.
public enum CloudLibraryFocus: Hashable, Sendable {
    /// The card of the game with this product id.
    case game(String)
    /// The detail's Play button.
    case play
    /// The detail's Close button.
    case close
    /// The detail's store button.
    case store
    /// The detail's store code, which opens the store page it encodes.
    case purchaseCode
    /// The detail's Add to library button.
    case addToLibrary
    /// The detail's Refresh title button.
    case refreshTitle
    /// The detail's button that shows the game's other generation's version.
    case otherVersion
    /// The detail's media tile at this index.
    case media(Int)
    /// The bundle picker's game with this product id.
    case bundleGame(String)
    /// A filter chip.
    case filter(CloudLibraryFilter)
    /// The search button or field.
    case search
    /// The Refresh button.
    case refresh
    /// A platform chip.
    case platform(CloudPlatformFilter)
    /// The page bar.
    case pageBar
    /// The page number field.
    case pageNumber
}
