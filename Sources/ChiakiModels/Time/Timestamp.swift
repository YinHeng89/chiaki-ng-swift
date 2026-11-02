import Foundation

/// The one conversion between dates and whole milliseconds since 1970.
///
/// The core, the bridge and the database all carry moments as milliseconds since 1970. Each caller keeps its
/// own marker for a missing time, such as `0` or a negative value; this type only converts.
public enum Timestamp {
    /// The whole milliseconds since 1970 that stand for a date.
    ///
    /// - Parameter date: The date.
    /// - Returns: The milliseconds, rounded to the nearest, with halves rounded away from zero.
    public static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The date that whole milliseconds since 1970 stand for.
    ///
    /// - Parameter milliseconds: The milliseconds; zero and negative values are dates like any other.
    /// - Returns: The date.
    public static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}
