import Foundation

/// Whether a focused slider is being navigated past or adjusted with the controller.
///
/// Confirm on a slider starts adjusting it and remembers its value at that moment, so Left and Right change the
/// value only while adjusting. Confirm again keeps the new value, and leaving restores navigation. The caller
/// restores ``adjusting(_:original:)``'s snapshot when the user cancels.
public enum SliderAdjustment<Slider: Equatable, Snapshot: Equatable>: Equatable {
    /// Directions move focus between controls.
    case navigating
    /// Directions change the slider's value; the snapshot is the value it had when adjusting started.
    case adjusting(Slider, original: Snapshot)

    /// The slider being adjusted, or `nil` while navigating.
    public var adjustingSlider: Slider? {
        if case .adjusting(let slider, _) = self {
            return slider
        }
        return nil
    }

    /// Reports whether the slider is the one being adjusted.
    ///
    /// - Parameter slider: The slider to check.
    /// - Returns: `true` while that slider is being adjusted.
    public func isAdjusting(_ slider: Slider) -> Bool {
        adjustingSlider == slider
    }

    /// Answers Confirm on a slider: starts adjusting it, or finishes adjusting it and keeps its value.
    ///
    /// - Parameters:
    ///   - slider: The focused slider.
    ///   - current: The value to restore if this adjustment is cancelled.
    public mutating func confirm(_ slider: Slider, current: Snapshot) {
        if isAdjusting(slider) {
            self = .navigating
        } else {
            self = .adjusting(slider, original: current)
        }
    }

    /// Returns to navigating, keeping whatever value the slider has.
    public mutating func leave() {
        self = .navigating
    }
}

extension SliderAdjustment: Sendable where Slider: Sendable, Snapshot: Sendable {}
