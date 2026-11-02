import SwiftUI
import DesignSystem

/// Debounces packet loss samples into a warning that appears only after sustained high loss and clears only
/// after sustained low loss.
public struct PacketLossWarning: Equatable {
    /// Creates a packet loss warning.
    public init() {
    }

    /// Where the warning stands between hidden and shown.
    public enum Phase: Equatable {
        /// No warning is shown and loss is below the raise threshold.
        case clear
        /// Loss has been high for the given number of consecutive samples, but not long enough to show.
        case rising(samples: Int)
        /// The warning is shown with the latest loss percentage.
        case shown(percent: Double)
        /// Loss has been low for the given number of consecutive samples while the warning still shows the
        /// last high percentage.
        case easing(samples: Int, percent: Double)
    }

    /// The loss percentage at or above which a sample counts as high.
    public static let raiseAtPercent = 2.0
    /// The loss percentage below which a sample counts as low.
    public static let clearBelowPercent = 0.5
    /// Consecutive high samples needed before the warning appears.
    public static let samplesToRaise = 3
    /// Consecutive low samples needed before the warning disappears.
    public static let samplesToClear = 6
    /// How often packet loss should be sampled.
    public static let sampleInterval = Duration.milliseconds(500)

    /// The current debounce phase.
    public private(set) var phase = Phase.clear

    /// The loss percentage to display, or `nil` when the warning is hidden.
    public var visiblePercent: Double? {
        switch phase {
        case .shown(let percent), .easing(_, let percent):
            percent
        case .clear, .rising:
            nil
        }
    }

    /// Feeds one packet loss sample and advances the phase; a shown warning tracks the latest high reading.
    /// - Parameter percent: The packet loss percentage measured over the last interval.
    public mutating func sample(_ percent: Double) {
        let high = percent >= Self.raiseAtPercent
        let low = percent < Self.clearBelowPercent
        switch phase {
        case .clear:
            phase = high
                ? raised(after: 1, percent: percent)
                : .clear
        case .rising(let samples):
            phase = high
                ? raised(after: samples + 1, percent: percent)
                : .clear
        case .shown(let shown):
            phase = low
                ? eased(after: 1, percent: shown)
                : .shown(percent: percent)
        case .easing(let samples, let shown):
            phase = low
                ? eased(after: samples + 1, percent: shown)
                : .shown(percent: percent)
        }
    }

    /// Hides the warning and forgets any partial run of samples.
    public mutating func reset() {
        phase = .clear
    }

    private func raised(after samples: Int, percent: Double) -> Phase {
        samples >= Self.samplesToRaise
            ? .shown(percent: percent)
            : .rising(samples: samples)
    }

    private func eased(after samples: Int, percent: Double) -> Phase {
        samples >= Self.samplesToClear
            ? .clear
            : .easing(samples: samples, percent: percent)
    }
}

/// A yellow glass capsule that shows the current packet loss percentage and ignores pointer input.
public struct PacketLossBadge: View {
    /// The packet loss percentage to show, rounded to one decimal place.
    public let percent: Double

    /// Creates a packet loss badge.
    ///
    /// - Parameter percent: The packet loss percentage to show, rounded to one decimal place.
    public init(percent: Double) {
        self.percent = percent
    }

    private var description: String {
        percent.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    public var body: some View {
        Label {
            Text("Packet loss \(description)").monospacedDigit()
        } icon: {
            Image(systemName: "wifi.exclamationmark")
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.yellow)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(AppGlass.control, in: .capsule)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Packet loss \(description)")
    }
}
