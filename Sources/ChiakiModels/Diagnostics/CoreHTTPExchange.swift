import Foundation

/// One recorded HTTP exchange, as the log lists it.
public struct CoreHTTPExchange: Equatable, Identifiable, Sendable {
    /// The exchange's sequence number.
    public let id: UInt64

    /// The part of the core that made it.
    public let area: CoreHTTPArea

    /// The credentials it carried.
    public let credentials: Set<CoreHTTPCredential>

    /// How the credentials are described.
    public let credentialLabel: String

    /// The request's label.
    public let label: String

    /// Which attempt this was.
    public let attempt: Int

    /// The HTTP method.
    public let method: String

    /// When it started.
    public let startedAt: Date

    /// How long it took.
    public let duration: Duration

    /// The scheme and host it went to.
    public let base: String

    /// The full address, with its secrets marked.
    public let url: CoreHTTPMarkedText

    /// The HTTP status, when a response arrived.
    public let status: Int?

    /// The status's reason phrase.
    public let reason: String

    /// Why no response arrived, when none did.
    public let transportError: CoreHTTPTransportError?

    /// Whether the exchange failed.
    public let failed: Bool

    /// How many bytes were sent.
    public let bytesSent: Int

    /// How many bytes were received.
    public let bytesReceived: Int

    /// Describes an exchange.
    ///
    /// - Parameters:
    ///   - id: The sequence number.
    ///   - area: The part of the core that made it.
    ///   - credentials: The credentials it carried.
    ///   - credentialLabel: How they are described.
    ///   - label: The request's label.
    ///   - attempt: Which attempt it was.
    ///   - method: The HTTP method.
    ///   - startedAt: When it started.
    ///   - duration: How long it took.
    ///   - base: The scheme and host.
    ///   - url: The full address.
    ///   - status: The HTTP status.
    ///   - reason: The reason phrase.
    ///   - transportError: Why no response arrived.
    ///   - failed: Whether it failed.
    ///   - bytesSent: How many bytes were sent.
    ///   - bytesReceived: How many bytes were received.
    public init(
        id: UInt64,
        area: CoreHTTPArea = .other,
        credentials: Set<CoreHTTPCredential> = [],
        credentialLabel: String = "",
        label: String = "",
        attempt: Int = 1,
        method: String = "GET",
        startedAt: Date = Date(timeIntervalSince1970: 0),
        duration: Duration = .zero,
        base: String,
        url: CoreHTTPMarkedText,
        status: Int? = 200,
        reason: String = "",
        transportError: CoreHTTPTransportError? = nil,
        failed: Bool = false,
        bytesSent: Int = 0,
        bytesReceived: Int = 0
    ) {
        self.id = id
        self.area = area
        self.credentials = credentials
        self.credentialLabel = credentialLabel
        self.label = label
        self.attempt = attempt
        self.method = method
        self.startedAt = startedAt
        self.duration = duration
        self.base = base
        self.url = url
        self.status = status
        self.reason = reason
        self.transportError = transportError
        self.failed = failed
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
    }
}

/// The part of the core that made an HTTP request.
public enum CoreHTTPArea: CaseIterable, Equatable, Hashable, Sendable {
    /// Signing users in and keeping their tokens.
    case users

    /// Finding, pairing and waking consoles.
    case consoles

    /// Reading the cloud catalog and the store.
    case catalog

    /// Reading trophy levels, trophy lists and each title's trophies.
    case trophies

    /// Reading message conversations and sending text in them.
    case messages

    /// Starting and running a stream.
    case play

    /// Anything else.
    case other
}

/// A kind of credential an HTTP request can carry.
public enum CoreHTTPCredential: CaseIterable, Equatable, Hashable, Sendable {
    /// A PSN account token.
    case accountToken

    /// The sign-in cookie.
    case signInCookie

    /// A GK session.
    case gkSession

    /// The client credentials.
    case clientCredentials

    /// A store session.
    case storeSession

    /// A sign-in grant.
    case signInGrant
}

/// Why an HTTP request failed before a response arrived.
public enum CoreHTTPTransportError: Equatable, Hashable, Sendable {
    /// The request was cancelled.
    case cancelled

    /// The request timed out.
    case timedOut

    /// The address was not valid.
    case invalidURL

    /// The server's certificate was not trusted.
    case tlsTrustFailed

    /// The proxy failed.
    case proxyFailed

    /// The connection dropped.
    case disconnected

    /// The response was too large.
    case responseTooLarge

    /// The request is not supported.
    case unsupported

    /// The HTTP backend failed.
    case backendFailure
}

/// The headers and bodies of one recorded HTTP exchange.
public struct CoreHTTPExchangeDetail: Equatable, Sendable {
    /// The request's headers.
    public let requestHeaders: [CoreHTTPHeader]

    /// The request's body.
    public let requestBody: CoreHTTPBody

    /// The response's headers.
    public let responseHeaders: [CoreHTTPHeader]

    /// The response's body.
    public let responseBody: CoreHTTPBody

    /// Describes an exchange's detail.
    ///
    /// - Parameters:
    ///   - requestHeaders: The request's headers.
    ///   - requestBody: The request's body.
    ///   - responseHeaders: The response's headers.
    ///   - responseBody: The response's body.
    public init(
        requestHeaders: [CoreHTTPHeader],
        requestBody: CoreHTTPBody,
        responseHeaders: [CoreHTTPHeader],
        responseBody: CoreHTTPBody
    ) {
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
    }
}

/// One recorded HTTP header.
public struct CoreHTTPHeader: Equatable, Sendable {
    /// The header's name.
    public let name: String

    /// The header's value, with its secrets marked.
    public let value: CoreHTTPMarkedText

    /// Describes a header.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - value: The value.
    public init(name: String, value: CoreHTTPMarkedText) {
        self.name = name
        self.value = value
    }
}

/// A recorded HTTP body as it is shown.
public struct CoreHTTPBody: Equatable, Sendable {
    /// The whole body's size in bytes.
    public let size: Int

    /// How many of those bytes the log kept.
    public let kept: Int

    /// Whether the log kept only the first part.
    public let truncated: Bool

    /// Whether the kept bytes are not UTF-8 text.
    public let binary: Bool

    /// The kept body as text, with its secrets marked.
    public let text: CoreHTTPMarkedText

    /// Describes a body.
    ///
    /// - Parameters:
    ///   - size: The whole size.
    ///   - kept: How many bytes were kept.
    ///   - truncated: Whether only the first part was kept.
    ///   - binary: Whether the bytes are not text.
    ///   - text: The kept text.
    public init(size: Int, kept: Int, truncated: Bool, binary: Bool, text: CoreHTTPMarkedText) {
        self.size = size
        self.kept = kept
        self.truncated = truncated
        self.binary = binary
        self.text = text
    }
}
