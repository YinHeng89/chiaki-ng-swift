/// The generation of a PlayStation console.
///
/// The raw values are the ones stored in `consoles.generation`.
public enum ConsoleKind: String, CaseIterable, Hashable, Sendable {
    /// A PlayStation 4.
    case ps4

    /// A PlayStation 5.
    case ps5
}
