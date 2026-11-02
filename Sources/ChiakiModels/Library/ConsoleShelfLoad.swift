/// Whether the console shelf waits for the console catalog before it shows anything.
///
/// The shelf shows a spinner instead of an empty shelf while the catalog loads, but only for
/// ``patience``: a catalog that takes longer shows whatever is known so the screen never stays blank.
public enum ConsoleShelfLoad: Equatable, Sendable {
    /// The catalog is read; the shelf shows the consoles.
    case loaded
    /// The catalog is loading and the shelf still waits for it.
    case waiting
    /// The catalog is still loading after ``patience``; the shelf shows what it has.
    case slow

    /// How long the shelf waits for the catalog before it shows what it has.
    public static let patience = Duration.seconds(2)

    /// Whether the shelf hides its consoles behind a spinner.
    public var isWaiting: Bool {
        self == .waiting
    }
}
