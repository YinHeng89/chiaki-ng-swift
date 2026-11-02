import Foundation

/// Paces HD rumble tones to what the controller's link can carry.
///
/// A tone is sent when it changes by at least ``step`` or every ``refreshInterval``, never faster than the
/// link's minimum interval.
public struct HDRumblePacer: Equatable, Sendable {
    /// How the controller is connected.
    public enum Link: Equatable, Sendable {
        /// USB.
        case usb

        /// Bluetooth, which needs more time between reports.
        case bluetooth

        /// The shortest gap allowed between two reports on this link: 30 ms over USB, 45 ms over Bluetooth.
        var minimumInterval: TimeInterval {
            switch self {
            case .usb:
                0.03
            case .bluetooth:
                0.045
            }
        }
    }

    /// What the controller was last told.
    public enum Output: Equatable, Sendable {
        /// Nothing is playing.
        case idle

        /// A tone is playing, sent at the given time.
        case playing(HDRumbleTone, sentAt: TimeInterval)
    }

    /// How often a steady tone is re-sent.
    public static let refreshInterval: TimeInterval = 0.045

    /// The smallest amplitude change that is sent straight away.
    public static let step: Float = 0.03

    /// What the controller was last told.
    public private(set) var output = Output.idle

    /// Creates an idle pacer.
    public init() {
    }

    /// Whether a tone is playing.
    public var isPlaying: Bool {
        output != .idle
    }

    /// The tone to send now, if any.
    ///
    /// - Parameters:
    ///   - tone: The tone wanted.
    ///   - now: The current time.
    ///   - link: The connection.
    /// - Returns: The tone to send, ``HDRumbleTone/silent`` to stop, or `nil` to send nothing.
    public mutating func next(_ tone: HDRumbleTone, at now: TimeInterval, over link: Link) -> HDRumbleTone? {
        switch output {
        case .idle:
            guard !tone.isSilent else {
                return nil
            }
            output = .playing(tone, sentAt: now)
            return tone
        case let .playing(sent, sentAt):
            let elapsed = now - sentAt
            if elapsed >= 0, elapsed < link.minimumInterval {
                return nil
            }
            if tone.isSilent {
                output = .idle
                return .silent
            }
            let changed = abs(tone.left - sent.left) >= Self.step || abs(tone.right - sent.right) >= Self.step
            guard changed || elapsed < 0 || elapsed >= Self.refreshInterval else {
                return nil
            }
            output = .playing(tone, sentAt: now)
            return tone
        }
    }

    /// Stops a playing tone.
    ///
    /// - Returns: ``HDRumbleTone/silent`` when something was playing, otherwise `nil`.
    public mutating func stop() -> HDRumbleTone? {
        guard isPlaying else {
            return nil
        }
        output = .idle
        return .silent
    }
}

/// The amplitude of each side of an HD rumble controller.
public struct HDRumbleTone: Equatable, Sendable {
    /// Both sides silent.
    public static let silent = HDRumbleTone(left: 0, right: 0)

    /// The left amplitude, 0 to 1.
    public var left: Float

    /// The right amplitude, 0 to 1.
    public var right: Float

    /// Creates a tone.
    ///
    /// - Parameters:
    ///   - left: The left amplitude.
    ///   - right: The right amplitude.
    public init(left: Float, right: Float) {
        self.left = left
        self.right = right
    }

    /// Whether neither side plays.
    public var isSilent: Bool {
        [left, right].allSatisfy { !$0.isFinite || $0 <= 0 }
    }

    /// The tone scaled by the user's strength.
    ///
    /// - Parameter strength: The strength, 0 to 1.
    /// - Returns: The scaled tone.
    public func scaled(by strength: Double) -> HDRumbleTone {
        let gain = strength.isFinite
            ? Float(max(0, min(1, strength)))
            : 0
        return HDRumbleTone(left: left * gain, right: right * gain)
    }
}
