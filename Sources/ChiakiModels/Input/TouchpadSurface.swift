/// A console touchpad's coordinate range.
public struct TouchpadSurface: Equatable, Sendable {
    /// The PS5 touchpad.
    public static let ps5 = TouchpadSurface(width: 1919, height: 1079)

    /// The PS4 touchpad.
    public static let ps4 = TouchpadSurface(width: 1920, height: 942)

    /// The largest horizontal coordinate.
    public let width: UInt16

    /// The largest vertical coordinate.
    public let height: UInt16

    /// Creates a surface.
    ///
    /// - Parameters:
    ///   - width: The largest horizontal coordinate.
    ///   - height: The largest vertical coordinate.
    public init(width: UInt16, height: UInt16) {
        self.width = width
        self.height = height
    }

    /// The width-to-height ratio.
    public var aspectRatio: Double {
        Double(width) / Double(height)
    }

    /// A contact at a normalised position, with id 0.
    ///
    /// - Parameters:
    ///   - normalizedX: The horizontal position, 0 to 1.
    ///   - normalizedY: The vertical position, 0 to 1.
    /// - Returns: The contact in touchpad units.
    public func point(normalizedX: Double, normalizedY: Double) -> ControllerTouch {
        ControllerTouch(id: 0, x: Self.scale(normalizedX, width), y: Self.scale(normalizedY, height))
    }

    /// A contact in the middle of a half, with an id reserved for bound touchpad presses.
    ///
    /// - Parameter region: The half.
    /// - Returns: The contact.
    public func press(_ region: TouchpadRegion) -> ControllerTouch {
        switch region {
        case .left:
            var touch = point(normalizedX: 0.25, normalizedY: 0.5)
            touch.id = 0x7e
            return touch
        case .right:
            var touch = point(normalizedX: 0.75, normalizedY: 0.5)
            touch.id = 0x7f
            return touch
        }
    }

    /// The half a contact is in.
    ///
    /// - Parameter touch: The contact.
    /// - Returns: The half.
    public func region(of touch: ControllerTouch) -> TouchpadRegion {
        touch.x < width / 2
            ? .left
            : .right
    }

    private static func scale(_ value: Double, _ limit: UInt16) -> UInt16 {
        guard value.isFinite else {
            return 0
        }
        return UInt16((max(0, min(1, value)) * Double(limit)).rounded())
    }
}

/// A half of the touchpad.
public enum TouchpadRegion: Equatable, Sendable {
    /// The left half.
    case left

    /// The right half.
    case right
}
