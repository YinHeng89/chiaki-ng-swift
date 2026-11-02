/// Decides which touchpad source owns the console touchpad when both are touched.
///
/// The first source to touch owns it; physical wins a tie. When the owner lifts while the other is still
/// touching, the other stays blocked until it lifts too, so a stray contact never jumps the cursor.
public struct TouchpadArbiter: Equatable, Sendable {
    /// Who holds the touchpad.
    public enum Phase: Equatable, Sendable {
        /// Nobody.
        case idle

        /// The source owns it.
        case owned(TouchpadSource)

        /// The source is touching but must lift before it may own it.
        case blocked(TouchpadSource)
    }

    /// Which sources are touching.
    public struct Contacts: Equatable, Sendable {
        /// Neither source.
        public static let none = Contacts(virtual: false, physical: false)

        /// Whether the virtual touchpad is touched.
        public var virtual: Bool

        /// Whether a physical touchpad is touched.
        public var physical: Bool

        /// Creates contacts.
        ///
        /// - Parameters:
        ///   - virtual: Whether the virtual touchpad is touched.
        ///   - physical: Whether a physical touchpad is touched.
        public init(virtual: Bool, physical: Bool) {
            self.virtual = virtual
            self.physical = physical
        }

        /// Reports whether the given source is currently touched.
        ///
        /// - Parameter source: The source to check.
        /// - Returns: `true` when that source has a contact.
        func touching(_ source: TouchpadSource) -> Bool {
            switch source {
            case .virtual:
                virtual
            case .physical:
                physical
            }
        }
    }

    /// The current phase.
    public private(set) var phase = Phase.idle

    /// Creates an idle arbiter.
    public init() {
    }

    /// The owning source, if any.
    public var owner: TouchpadSource? {
        guard case .owned(let source) = phase else {
            return nil
        }
        return source
    }

    /// Whether a source's contacts reach the console.
    ///
    /// - Parameter source: The source.
    /// - Returns: `true` when it owns the touchpad.
    public func admits(_ source: TouchpadSource) -> Bool {
        owner == source
    }

    /// Whether a source's contacts are held back.
    ///
    /// - Parameter source: The source.
    /// - Returns: `true` when another source owns or a source is blocked.
    public func suppresses(_ source: TouchpadSource) -> Bool {
        phase != .idle && !admits(source)
    }

    /// Updates ownership from the current contacts.
    ///
    /// - Parameter contacts: Which sources are touching.
    public mutating func update(_ contacts: Contacts) {
        switch phase {
        case .idle:
            phase = Self.claim(contacts, blocked: nil)
        case .owned(let source):
            guard !contacts.touching(source) else {
                return
            }
            phase = contacts.touching(source.other)
                ? .blocked(source.other)
                : .idle
        case .blocked(let source):
            phase = Self.claim(contacts, blocked: contacts.touching(source)
                ? source
                : nil)
        }
    }

    private static func claim(_ contacts: Contacts, blocked: TouchpadSource?) -> Phase {
        for source in [TouchpadSource.physical, .virtual]
            where source != blocked && contacts.touching(source) {
            return .owned(source)
        }
        return blocked.map(Phase.blocked) ?? .idle
    }
}

/// Where touchpad contacts come from.
public enum TouchpadSource: Equatable, Sendable {
    /// The on-screen virtual touchpad.
    case virtual

    /// A physical controller touchpad.
    case physical

    /// The opposite source: physical for virtual and virtual for physical.
    var other: TouchpadSource {
        switch self {
        case .virtual:
            .physical
        case .physical:
            .virtual
        }
    }
}
