import Foundation

/// A named set of input bindings.
public struct InputPreset: Codable, Equatable, Sendable, Identifiable {
    /// The id of the built-in ``standard`` preset.
    public static let defaultID = UUID(uuidString: "9AF137F1-2BB0-4878-A82B-07D652849CD0")!

    /// The gamepad button that holds gyro steering in ``withoutGyro``.
    public static let gyroHoldButton = 8

    /// The preset's id.
    public var id: UUID

    /// The preset's name.
    public var name: String

    /// The bindings.
    public var bindings: [InputBinding]

    /// Creates a preset.
    ///
    /// - Parameters:
    ///   - id: The id.
    ///   - name: The name.
    ///   - bindings: The bindings.
    public init(id: UUID, name: String, bindings: [InputBinding]) {
        self.id = id
        self.name = name
        self.bindings = bindings
    }

    /// The built-in keyboard and gamepad layout.
    public static var standard: Self {
        let keys: [(Int, String)] = [
            (36, "Return"), (51, "Delete"), (42, "\\"), (8, "C"),
            (123, "←"), (124, "→"), (126, "↑"), (125, "↓"),
            (19, "2"), (20, "3"), (23, "5"), (22, "6"), (31, "O"), (3, "F"), (17, "T"), (53, "Escape"),
            (18, "1"), (21, "4"), (0, "A"), (2, "D"), (13, "W"), (1, "S"),
            (38, "J"), (40, "K"), (34, "I"), (46, "M")
        ]
        var bindings = zip(PlayStationControl.allCases, keys).map { target, key in
            InputBinding(source: .macKey, code: key.0, label: key.1, target: target)
        }
        let buttons = [0, 1, 2, 3, 13, 14, 11, 12, 9, 10, 7, 8, 6, 4, 20, 5]
        bindings += zip(PlayStationControl.allCases, buttons).map { target, code in
            InputBinding(source: .gamepadButton, code: code, label: "", target: target)
        }
        return Self(id: defaultID, name: "Standard", bindings: bindings)
    }

    /// The preset adapted for a controller without a touchpad: Back clicks the touchpad and the misc button
    /// is Share.
    public var withoutTouchpad: Self {
        var copy = self
        copy.bindings.removeAll {
            $0.source == .gamepadButton && ($0.target == .touchpad || $0.target == .share)
        }
        copy.bindings.append(InputBinding(source: .gamepadButton, code: 4, label: "", target: .touchpad))
        copy.bindings.append(InputBinding(source: .gamepadButton, code: 15, label: "", target: .share))
        return copy
    }

    /// The gamepad button that is the touchpad on controllers that have one.
    public static let touchpadButton = 20

    /// The preset for a controller without a touchpad, moving the touchpad off ``touchpadButton`` to the
    /// first free of Back and Misc 1. A preset that binds the touchpad elsewhere is returned unchanged.
    public var touchpadOffItsButton: Self {
        let pad = bindings.filter {
            $0.source == .gamepadButton
        }
        guard pad.contains(where: { $0.target == .touchpad && $0.code == Self.touchpadButton }),
              let free = [4, 15].first(where: { code in !pad.contains { $0.code == code } }) else {
            return self
        }
        var copy = self
        copy.bindings.removeAll {
            $0.source == .gamepadButton && $0.target == .touchpad
        }
        copy.bindings.append(InputBinding(source: .gamepadButton, code: free, label: "", target: .touchpad))
        return copy
    }

    /// The preset adapted for a controller without gyro: ``gyroHoldButton`` holds gyro steering.
    public var withoutGyro: Self {
        var copy = self
        copy.bindings.removeAll {
            $0.source == .gamepadButton && $0.target == .gyroHold
        }
        copy.bindings.append(InputBinding(source: .gamepadButton, code: Self.gyroHoldButton, label: "",
                                          target: .gyroHold))
        return copy
    }
}

extension InputPreset {
    /// What else changed when an input was assigned to a control.
    public struct Assignment: Equatable, Sendable {
        /// The control that held the input before, if any. Gyro hold never counts, because it shares a button
        /// on purpose.
        public var displaced: PlayStationControl?

        /// The input the displaced control received in exchange, or `nil` when it was left unbound.
        public var exchanged: InputBinding?

        /// Creates an assignment result.
        ///
        /// - Parameters:
        ///   - displaced: The control that lost the input.
        ///   - exchanged: The input it received instead.
        public init(displaced: PlayStationControl? = nil, exchanged: InputBinding? = nil) {
            self.displaced = displaced
            self.exchanged = exchanged
        }
    }

    /// Binds an input to the binding's control, swapping when another control already uses that input.
    ///
    /// The control's previous input of the same source moves to the control that held the new one, so
    /// nothing is silently lost. Gyro hold shares a button with another control instead of displacing it.
    ///
    /// - Parameter binding: The input and the control it should drive.
    /// - Returns: The control that was displaced and what it received.
    @discardableResult
    public mutating func assign(_ binding: InputBinding) -> Assignment {
        let source = binding.source
        let previous = bindings.first { $0.source == source && $0.target == binding.target }
        let holder = binding.target == .gyroHold
            ? nil
            : bindings.first {
                $0.source == source && $0.code == binding.code && $0.target != binding.target
                    && $0.target != .gyroHold
            }
        bindings.removeAll { $0.source == source && $0.target == binding.target }
        guard let holder else {
            bindings.append(binding)
            return Assignment()
        }
        bindings.removeAll { $0 == holder }
        bindings.append(binding)
        guard let previous, previous.code != binding.code else {
            return Assignment(displaced: holder.target)
        }
        let exchanged = InputBinding(
            source: source, code: previous.code, label: previous.label, target: holder.target
        )
        bindings.append(exchanged)
        return Assignment(displaced: holder.target, exchanged: exchanged)
    }

    /// Removes every input of one source from a control.
    ///
    /// - Parameters:
    ///   - target: The control.
    ///   - source: The kind of input to remove.
    public mutating func clear(_ target: PlayStationControl, source: InputSource) {
        bindings.removeAll { $0.source == source && $0.target == target }
    }
}
