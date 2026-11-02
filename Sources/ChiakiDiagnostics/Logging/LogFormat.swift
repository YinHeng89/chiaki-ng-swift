import ChiakiModels
import Foundation

/// Short, consistent renderings of values that appear in log lines.
public enum LogFormat {
    /// The first bytes of `data` in hex, with an ellipsis when more follow.
    ///
    /// - Parameters:
    ///   - data: The bytes to show.
    ///   - bytes: How many leading bytes to show.
    /// - Returns: The hex prefix, or `none` for empty data.
    public static func hexPrefix(_ data: Data, bytes: Int = 4) -> String {
        guard !data.isEmpty else {
            return "none"
        }
        let shown = Hex.encode(data.prefix(max(1, bytes)))
        return data.count > bytes
            ? shown + "…"
            : shown
    }

    /// The first eight characters of a UUID, enough to correlate lines.
    ///
    /// - Parameter id: The identifier.
    /// - Returns: The lowercase prefix with an ellipsis.
    public static func idPrefix(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8)) + "…"
    }

    /// The first characters of `text`, with an ellipsis when it is longer.
    ///
    /// - Parameters:
    ///   - text: The text to shorten.
    ///   - characters: How many characters to keep.
    /// - Returns: The prefix, or `text` unchanged when it is short enough.
    public static func textPrefix(_ text: String, characters: Int = 6) -> String {
        guard text.count > characters else {
            return text
        }
        return String(text.prefix(characters)) + "…"
    }

    /// A MAC address as contiguous lowercase hex.
    ///
    /// - Parameter data: The address bytes.
    /// - Returns: The hex text, or `unknown` for empty data.
    public static func mac(_ data: Data) -> String {
        data.isEmpty
            ? "unknown"
            : Hex.encode(data)
    }

    /// `yes` or `no`.
    ///
    /// - Parameter value: The flag.
    /// - Returns: The word for the flag.
    public static func yesNo(_ value: Bool) -> String {
        value
            ? "yes"
            : "no"
    }

    /// A duration in whole milliseconds.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: The truncated millisecond count.
    public static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    /// A byte count in B, KB or MB.
    ///
    /// - Parameter bytes: The byte count.
    /// - Returns: The size with one decimal above a kilobyte.
    public static func size(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// A lifetime in seconds with the instant it ends.
    ///
    /// - Parameters:
    ///   - seconds: The lifetime.
    ///   - now: The instant it starts.
    /// - Returns: The seconds and the ISO 8601 end instant.
    public static func expiry(seconds: Int, now: Date) -> String {
        let instant = now.addingTimeInterval(TimeInterval(seconds))
        return "\(seconds) s (until \(instant.ISO8601Format()))"
    }

    private static let errnoNames: [Int32: String] = [
        EPERM: "EPERM", EACCES: "EACCES", EINVAL: "EINVAL", ENOSPC: "ENOSPC", EMFILE: "EMFILE",
        ENFILE: "ENFILE", EAGAIN: "EAGAIN", ENOBUFS: "ENOBUFS", EADDRINUSE: "EADDRINUSE",
        EADDRNOTAVAIL: "EADDRNOTAVAIL", ENETDOWN: "ENETDOWN", ENETUNREACH: "ENETUNREACH",
        EHOSTDOWN: "EHOSTDOWN", EHOSTUNREACH: "EHOSTUNREACH", ECONNREFUSED: "ECONNREFUSED",
        ECONNRESET: "ECONNRESET", ETIMEDOUT: "ETIMEDOUT", EMSGSIZE: "EMSGSIZE", ENOTSOCK: "ENOTSOCK",
        EBADF: "EBADF", EINTR: "EINTR"
    ]

    /// An `errno` value with its symbolic name and system description.
    ///
    /// - Parameter code: The error number; its sign is ignored.
    /// - Returns: The name and description, or the number when the name is not known.
    public static func errno(_ code: Int32) -> String {
        let value = abs(code)
        let text = String(cString: strerror(value))
        guard let name = errnoNames[value] else {
            return "errno \(value) (\(text))"
        }
        return "\(name) (\(text))"
    }

    /// An error named without its payload, so associated values never reach the log.
    ///
    /// - Parameter error: The error.
    /// - Returns: The case name when it is short and plain, otherwise the type, domain and code.
    public static func error(_ error: Error) -> String {
        let text = String(describing: error)
        if text.count <= 80,
           text.range(of: "^[A-Za-z]+(\\([0-9, -]*\\))?$", options: .regularExpression) != nil {
            return text
        }
        let bridged = error as NSError
        return "\(type(of: error)) (domain \(bridged.domain), code \(bridged.code))"
    }

    private static let urlErrorNames: [Int: String] = [
        -999: "cancelled", -1000: "bad URL", -1001: "timed out", -1003: "cannot find host",
        -1004: "cannot connect to host", -1005: "network connection lost", -1006: "DNS lookup failed",
        -1009: "not connected to the internet", -1011: "bad server response",
        -1017: "cannot parse response", -1020: "data not allowed on this network",
        -1103: "response larger than allowed", -1200: "TLS connection failed",
        -1201: "server certificate has a bad date", -1202: "server certificate untrusted",
        -1203: "server certificate has an unknown root", -1204: "server certificate not yet valid",
        -1205: "client certificate rejected", -1206: "client certificate required"
    ]

    /// A URL loading error code with its meaning.
    ///
    /// - Parameter code: The `URLError` code, or `nil` for an error that is not one.
    /// - Returns: The code and its meaning.
    public static func urlError(_ code: Int?) -> String {
        guard let code else {
            return "non-URL error"
        }
        return "URL error \(code) (\(urlErrorNames[code] ?? "unrecognised"))"
    }
}
