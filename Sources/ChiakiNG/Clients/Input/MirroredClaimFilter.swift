import CInput

/// Holds a free controller's seat claim briefly and drops it when player one made the same press at the same
/// moment.
///
/// One physical controller can appear twice, for example an Xbox controller that stays paired over Bluetooth
/// while it charges over USB, or a pad that Steam also exposes as a virtual controller. Every press then arrives on
/// both devices, so the second copy would take a couch seat whenever player one pressed Options. A real second
/// player never presses the same button within the same instant, so a claim is kept for ``window`` and released
/// only when player one made no matching press within it, on either side.
struct MirroredClaimFilter {
    /// A claim waiting for its window to pass.
    struct Held: Equatable {
        /// The claiming controller's id.
        let instance: UInt32
        /// The button that claimed.
        let control: Int32
        /// When it was pressed, in input-clock microseconds.
        let time: UInt64
    }

    private struct Press {
        let control: Int32
        let value: Int32
        let time: UInt64
    }

    /// How close in time player one's press must be for a claim to count as a copy, in microseconds.
    static let window: UInt64 = 150_000
    /// How many of player one's button changes are remembered.
    static let remembered = 32

    private var playerOne: [Press] = []
    /// The claims waiting for their window to pass, in the order they claimed.
    private(set) var held: [Held] = []

    /// Notes one of player one's button changes.
    ///
    /// - Parameter event: The event; anything but a button change is ignored.
    mutating func notePlayerOne(_ event: nx_input_event) {
        guard event.kind == ControllerInputEvent.button else {
            return
        }
        playerOne.append(Press(control: event.control, value: event.value, time: event.timestamp_us))
        if playerOne.count > Self.remembered {
            playerOne.removeFirst(playerOne.count - Self.remembered)
        }
    }

    /// Holds a claim until its window passes; a controller that already holds a claim keeps the first.
    ///
    /// - Parameter event: The press that claimed.
    mutating func hold(_ event: nx_input_event) {
        guard !held.contains(where: { $0.instance == event.instance }) else {
            return
        }
        held.append(Held(instance: event.instance, control: event.control, time: event.timestamp_us))
    }

    /// Takes the claims whose window has passed and that no press of player one's mirrors.
    ///
    /// - Parameter now: The input clock's time, in microseconds.
    /// - Returns: The controllers whose claims stand, in the order they claimed.
    mutating func release(now: UInt64) -> [UInt32] {
        let due = held.filter { now >= $0.time + Self.window }
        held.removeAll { now >= $0.time + Self.window }
        return due.filter { !mirrors($0) }.map(\.instance)
    }

    /// Forgets a controller's held claim, as when it disconnects.
    ///
    /// - Parameter instance: The controller's id.
    mutating func forget(_ instance: UInt32) {
        held.removeAll { $0.instance == instance }
    }

    private func mirrors(_ claim: Held) -> Bool {
        playerOne.contains { press in
            press.control == claim.control && press.value != 0
                && max(press.time, claim.time) - min(press.time, claim.time) <= Self.window
        }
    }
}
