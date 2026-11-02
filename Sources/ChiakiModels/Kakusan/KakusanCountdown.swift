import Foundation

/// Formats the time left until a Kakusan deadline.
public enum KakusanCountdown {
    /// The time left, as minutes and seconds, with hours once an hour or more is left.
    ///
    /// - Parameters:
    ///   - deadline: When the time runs out.
    ///   - now: The current moment.
    /// - Returns: The time left, never below zero.
    public static func remaining(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        guard seconds >= 3600 else {
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
