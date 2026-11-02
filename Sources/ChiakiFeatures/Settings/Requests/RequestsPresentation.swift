import ChiakiModels
import ChiakiDiagnostics
import Foundation

/// Presentation of request areas.
extension CoreHTTPArea {
    /// The area's name in the filter and request rows.
    public var title: String {
        switch self {
        case .users:
            "Sign-in"
        case .consoles:
            "Consoles"
        case .catalog:
            "Catalog"
        case .trophies:
            "Trophies"
        case .messages:
            "Messages"
        case .play:
            "Play"
        case .other:
            "Other"
        }
    }
}

/// Presentation of request credentials.
extension CoreHTTPCredential {
    /// The credential's name in the filter and request rows.
    public var title: String {
        switch self {
        case .accountToken:
            "Account token"
        case .signInCookie:
            "Sign-in cookie"
        case .gkSession:
            "GK session"
        case .clientCredentials:
            "Client credentials"
        case .storeSession:
            "Store session"
        case .signInGrant:
            "Sign-in grant"
        }
    }
}

/// Presentation of credential filters.
extension RequestsReducer.CredentialFilter {
    /// The filter's name in the filter controls.
    public var title: String {
        switch self {
        case .anonymous:
            "Anonymous"
        case .carried(let credential):
            credential.title
        }
    }
}

/// Presentation of secret kinds in masked text.
extension CoreHTTPSecretKind {
    /// The lowercase word used inside a mask for this kind of secret.
    public var title: String {
        switch self {
        case .credential:
            "credential"
        case .cookie:
            "cookie"
        case .session:
            "session"
        case .parameter:
            "parameter"
        case .field:
            "field"
        case .body:
            "body"
        }
    }
}

/// Presentation of transport errors.
extension CoreHTTPTransportError {
    /// A short description shown in place of a status code.
    public var title: String {
        switch self {
        case .cancelled:
            "Cancelled"
        case .timedOut:
            "Timed out"
        case .invalidURL:
            "Invalid URL"
        case .tlsTrustFailed:
            "TLS trust failed"
        case .proxyFailed:
            "Proxy failed"
        case .disconnected:
            "Disconnected"
        case .responseTooLarge:
            "Response too large"
        case .unsupported:
            "Unsupported"
        case .backendFailure:
            "Failed"
        }
    }
}

/// Renders marked text with its secrets masked unless revealed.
public enum RequestMasking {
    /// Returns the placeholder shown in place of a secret, naming its kind and length.
    public static func mask(_ span: CoreHTTPSecretSpan) -> String {
        "[\(span.kind.title), \(span.length) bytes]"
    }

    /// Returns the text with the secrets of the given part masked unless they are in the revealed set.
    public static func shown(
        _ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart, revealed: Set<RequestsReducer.Secret>
    ) -> String {
        text.shown(revealing: { revealed.contains(RequestsReducer.Secret(part, $0)) }, mask: mask)
    }

    /// Returns the text with every secret masked.
    public static func masked(_ text: CoreHTTPMarkedText) -> String {
        text.shown(revealing: { _ in false }, mask: mask)
    }
}

/// A base URL offered as a request filter, with its request counts.
public struct RequestBaseChoice: Equatable, Identifiable, Sendable {
    /// The base URL.
    public let base: String
    /// The number of requests made to the base since the totals were last reset.
    public let lifetime: Int
    /// The number of exchanges to the base still kept in the log.
    public let kept: Int
    /// Whether the filter for this base is on.
    public let chosen: Bool

    /// The base URL, which identifies the choice.
    public var id: String {
        base
    }

    /// The base URL without its scheme.
    public var host: String {
        base.range(of: "://").map { String(base[$0.upperBound...]) } ?? base
    }

    /// Returns a choice for every base in the totals, the kept exchanges or the chosen set, ordered by
    /// lifetime count and then by name.
    public static func choices(
        totals: CoreHTTPTotals, exchanges: [CoreHTTPExchange], chosen: Set<String>
    ) -> [RequestBaseChoice] {
        var kept: [String: Int] = [:]
        for exchange in exchanges {
            kept[exchange.base, default: 0] += 1
        }
        let bases = Set(totals.bases.keys).union(kept.keys).union(chosen)
        return bases.map { base in
            RequestBaseChoice(
                base: base, lifetime: totals.bases[base]?.requests ?? 0, kept: kept[base] ?? 0,
                chosen: chosen.contains(base)
            )
        }
        .sorted { left, right in
            left.lifetime != right.lifetime
                ? left.lifetime > right.lifetime
                : left.base < right.base
        }
    }
}

/// The display strings for one exchange in the request list.
public struct RequestRowPresentation: Equatable {
    /// The local time the exchange started, as hours, minutes and seconds.
    public let time: String
    /// The HTTP method.
    public let method: String
    /// The base URL.
    public let base: String
    /// The masked path after the base, or a slash when there is none.
    public let path: String
    /// The status code, or a transport error description when there is no response.
    public let status: String
    /// Whether the exchange failed.
    public let failed: Bool
    /// The exchange's duration in milliseconds or seconds.
    public let duration: String
    /// The size of the received bytes.
    public let size: String
    /// The names of the credentials carried, or Anonymous when there were none.
    public let credentials: [String]
    /// The area's name.
    public let area: String

    /// Formats the exchange for display, showing its start time in the given time zone.
    public init(_ exchange: CoreHTTPExchange, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: exchange.startedAt)
        time = String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        method = exchange.method
        base = exchange.base
        let rest = RequestMasking.masked(exchange.url.dropping(prefix: exchange.base.utf8.count))
        path = rest.isEmpty
            ? "/"
            : rest
        if let code = exchange.status {
            status = String(code)
        } else {
            status = exchange.transportError?.title ?? "Failed"
        }
        failed = exchange.failed
        duration = Self.duration(exchange.duration)
        size = LogFormat.size(exchange.bytesReceived)
        credentials = exchange.credentials.isEmpty
            ? ["Anonymous"]
            : CoreHTTPCredential.allCases.filter(exchange.credentials.contains).map(\.title)
        area = exchange.area.title
    }

    /// Formats a duration in whole milliseconds below a second and in seconds with two decimals otherwise.
    public static func duration(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        if milliseconds < 1000 {
            return "\(Int(milliseconds.rounded())) ms"
        }
        return String(format: "%.2f s", milliseconds / 1000)
    }
}

/// Builds the text copied from an open exchange.
public enum RequestCopy {
    /// Returns a curl command that repeats the request, with only revealed secrets unmasked.
    public static func curl(
        _ exchange: CoreHTTPExchange, _ detail: CoreHTTPExchangeDetail, revealed: Set<RequestsReducer.Secret>
    ) -> String {
        let url = RequestMasking.shown(exchange.url, part: .url, revealed: revealed)
        var lines = ["curl -X \(exchange.method) \(quoted(url))"]
        for (index, header) in detail.requestHeaders.enumerated() {
            let value = RequestMasking.shown(header.value, part: .requestHeader(index), revealed: revealed)
            lines.append("  -H \(quoted("\(header.name): \(value)"))")
        }
        let body = detail.requestBody
        if !body.binary, !body.text.isEmpty {
            lines
                .append(
                    "  --data-raw \(quoted(RequestMasking.shown(body.text, part: .requestBody, revealed: revealed)))"
                )
        }
        return lines.joined(separator: " \\\n")
    }

    /// Returns the response's status line, headers and body, with only revealed secrets unmasked, or the
    /// transport error when there was no response.
    public static func response(
        _ exchange: CoreHTTPExchange, _ detail: CoreHTTPExchangeDetail, revealed: Set<RequestsReducer.Secret>
    ) -> String {
        guard let status = exchange.status else {
            return exchange.transportError?.title ?? "Failed"
        }
        var lines = [exchange.reason.isEmpty
            ? "HTTP \(status)"
            : "HTTP \(status) \(exchange.reason)"]
        for (index, header) in detail.responseHeaders.enumerated() {
            lines.append("\(header.name): "
                + RequestMasking.shown(header.value, part: .responseHeader(index), revealed: revealed))
        }
        lines.append("")
        let body = detail.responseBody
        if body.binary {
            lines.append("Binary body, \(LogFormat.size(body.size))")
        } else {
            lines.append(RequestMasking.shown(body.text, part: .responseBody, revealed: revealed))
        }
        return lines.joined(separator: "\n")
    }

    /// Quotes text for a POSIX shell with single quotes.
    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
