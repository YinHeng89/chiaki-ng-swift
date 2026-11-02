import Foundation

/// The `key=value` diagnostics the core attaches to a stream failure, parsed into numbers with readable stage
/// and quit names.
public struct StreamFailureDiagnostics: Equatable, Sendable {
    /// Each numeric field, decimal or `0x` hexadecimal, keeping the first occurrence of a key.
    public let fields: [String: Int]
    /// The original diagnostics text.
    public let raw: String

    /// Parses space-separated `key=value` diagnostics, failing when the text is missing or empty.
    ///
    /// - Parameter raw: The diagnostics text.
    public init?(_ raw: String?) {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        var fields: [String: Int] = [:]
        for token in raw.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, fields[String(parts[0])] == nil else {
                continue
            }
            let text = String(parts[1])
            let value = text.hasPrefix("0x")
                ? Int(text.dropFirst(2), radix: 16)
                : Int(text)
            if let value {
                fields[String(parts[0])] = value
            }
        }
        self.fields = fields
        self.raw = raw
    }

    /// Reads a quoted text field.
    ///
    /// - Parameter key: The field name.
    /// - Returns: The text inside the quotes that follow the key, up to the end when the quote is
    ///   unterminated, or `nil` when the field is absent.
    public func text(_ key: String) -> String? {
        guard let start = raw.range(of: "\(key)=\"") else {
            return nil
        }
        let rest = raw[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else {
            return String(rest)
        }
        return String(rest[..<end])
    }

    /// The numeric stage the stream reached.
    public var stage: Int? {
        fields["stage"]
    }

    /// A readable name for the stage, or `nil` when the stage is missing or unknown.
    public var stageName: String? {
        stage.flatMap {
            Self.stageNames[$0]
        }
    }

    /// A readable reason the console quit, or `nil` when it did not quit or the code is unknown.
    public var quitName: String? {
        fields["quit"].flatMap {
            $0 == 0
                ? nil
                : Self.quitNames[$0]
        }
    }

    /// The console port the failed stage uses on a local route, or `nil` for remote routes and stages without
    /// a fixed port.
    public var localPort: Int? {
        guard fields["route"] == 1, let stage else {
            return nil
        }
        switch stage {
        case 1, 3, 4, 5, 6, 7:
            return 9295
        case 8:
            return 9297
        case 10, 11, 12, 13, 14, 15, 21:
            return 9296
        default:
            return nil
        }
    }

    private static let stageNames: [Int: String] = [
        0: "session", 1: "console address lookup", 2: "registration", 3: "session init", 4: "Ctrl startup",
        5: "Ctrl session ID", 6: "Ctrl feature setup", 7: "Ctrl receive", 8: "network calibration",
        9: "remote route switch", 10: "stream transport connection", 11: "stream handshake (BANG)",
        12: "stream encryption setup", 13: "stream format negotiation", 14: "media stream",
        15: "controller delivery", 16: "PSN session creation", 17: "PSN console readiness",
        18: "control route hole punching", 19: "data route hole punching", 20: "cloud provisioning",
        21: "stream preparation", 22: "session cleanup", 23: "cloud account authorization",
        24: "cloud client identification", 25: "cloud configuration", 26: "cloud session creation",
        27: "cloud streaming authorization", 28: "cloud entitlement authorization", 29: "cloud session lock",
        30: "cloud datacenter selection", 31: "cloud streaming slot allocation",
        32: "PS Now title preparation"
    ]

    private static let quitNames: [Int: String] = [
        1: "stopped", 2: "session request failed for an unknown reason",
        3: "the console refused the session request", 4: "Remote Play is already in use",
        5: "Remote Play crashed on the console", 6: "Remote Play versions do not match",
        7: "Ctrl failed for an unknown reason", 8: "the Ctrl connection could not be opened",
        9: "the console refused the Ctrl connection", 10: "the stream connection failed",
        11: "the console disconnected the stream", 12: "the console shut the stream down",
        13: "PSN registration failed"
    ]
}
