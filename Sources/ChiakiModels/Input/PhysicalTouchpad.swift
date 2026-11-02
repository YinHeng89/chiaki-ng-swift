/// Maps fingers on a physical touchpad onto the console touchpad's two slots.
///
/// Each new contact gets a 7-bit id not in use by other touch sources, so the console never sees one id for two
/// fingers.
public struct PhysicalTouchpad: Equatable, Sendable {
    /// A finger on one of possibly several touchpads.
    public struct Finger: Hashable, Sendable {
        /// The touchpad index.
        public let touchpad: Int

        /// The finger index on that touchpad.
        public let finger: Int

        /// Creates a finger.
        ///
        /// - Parameters:
        ///   - touchpad: The touchpad index.
        ///   - finger: The finger index.
        public init(touchpad: Int, finger: Int) {
            self.touchpad = touchpad
            self.finger = finger
        }
    }

    /// One console slot.
    public enum Slot: Equatable, Sendable {
        /// Unused.
        case free

        /// Held by a finger with its console contact.
        case contact(Finger, ControllerTouch)
    }

    /// The console touchpad contacts are placed on.
    public let surface: TouchpadSurface

    /// The two slots.
    public private(set) var slots: [Slot] = [.free, .free]

    private var nextID: UInt8 = 0

    /// Creates an empty touchpad.
    ///
    /// - Parameter surface: The console touchpad.
    public init(surface: TouchpadSurface = .ps5) {
        self.surface = surface
    }

    /// Whether any finger is down.
    public var isActive: Bool {
        slots.contains { $0 != .free }
    }

    /// The contacts to send.
    public var touches: ControllerTouchSlots {
        ControllerTouchSlots(first: touch(in: slots[0]), second: touch(in: slots[1]))
    }

    /// Places a finger in a free slot, ignoring it when none is free.
    ///
    /// - Parameters:
    ///   - finger: The finger.
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 to 1.
    ///   - avoiding: Contact ids other sources hold.
    public mutating func down(_ finger: Finger, x: Double, y: Double, avoiding: Set<UInt8> = []) {
        guard index(of: finger) == nil, let free = slots.firstIndex(of: .free) else {
            return
        }
        var touch = surface.point(normalizedX: x, normalizedY: y)
        touch.id = allocateID(avoiding: avoiding.union(touches.ids))
        slots[free] = .contact(finger, touch)
    }

    /// Moves a placed finger.
    ///
    /// - Parameters:
    ///   - finger: The finger.
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 to 1.
    public mutating func moved(_ finger: Finger, x: Double, y: Double) {
        guard let slot = index(of: finger), case .contact(_, var touch) = slots[slot] else {
            return
        }
        let position = surface.point(normalizedX: x, normalizedY: y)
        touch.x = position.x
        touch.y = position.y
        slots[slot] = .contact(finger, touch)
    }

    /// Lifts a finger.
    ///
    /// - Parameter finger: The finger.
    public mutating func up(_ finger: Finger) {
        guard let slot = index(of: finger) else {
            return
        }
        slots[slot] = .free
    }

    /// Lifts every finger.
    public mutating func reset() {
        slots = [.free, .free]
    }

    private func index(of finger: Finger) -> Int? {
        slots.firstIndex { slot in
            guard case .contact(let held, _) = slot else {
                return false
            }
            return held == finger
        }
    }

    private func touch(in slot: Slot) -> ControllerTouch? {
        guard case .contact(_, let touch) = slot else {
            return nil
        }
        return touch
    }

    private mutating func allocateID(avoiding: Set<UInt8>) -> UInt8 {
        var candidate = nextID
        while avoiding.contains(candidate) {
            candidate = (candidate + 1) & 0x7f
        }
        nextID = (candidate + 1) & 0x7f
        return candidate
    }
}
