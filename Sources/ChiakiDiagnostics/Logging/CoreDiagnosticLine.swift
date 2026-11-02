/// Rewrites the core's terse attempt summary lines into text a reader can act on.
public enum CoreDiagnosticLine {
    /// Explains a dropped-record count, removes a zero count and leaves every other line unchanged.
    ///
    /// - Parameter raw: The line as the core wrote it.
    /// - Returns: The line to log.
    public static func format(_ raw: String) -> String {
        guard raw.hasPrefix("core attempt="),
              let range = raw.range(of: " dropped=")
        else {
            return raw
        }
        let afterKey = raw[range.upperBound...]
        let digits = afterKey.prefix {
            $0.isNumber
        }
        let rest = afterKey.dropFirst(digits.count).drop {
            $0 == " "
        }
        let head = raw[..<range.lowerBound]
        if rest.hasPrefix("diagnostics queue overflow or contention") {
            return "\(head) the core dropped \(digits) diagnostic records before the app read them: its "
                + "256-record queue was full (224 for non-error records) or was busy when a core thread wrote, "
                + "because another writer or the app's reader held it; the core does not say which, and the "
                + "records are lost"
        }
        if digits == "0" {
            return "\(head) \(rest)"
        }
        return raw
    }
}
