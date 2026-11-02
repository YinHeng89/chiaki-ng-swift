import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads and clears the open core's log of HTTP exchanges.
///
/// Reading copies the log on a background task, so it never blocks the caller's actor.
public struct HTTPCallsBridge: Sendable {
    /// The core is not open, so there is no log to read.
    public struct Closed: Error, Equatable, Sendable {
        /// Creates the failure.
        public init() {}
    }

    private final class LogCollector: @unchecked Sendable {
        var exchanges: [CoreHTTPExchange] = []
    }

    private final class DetailCollector: @unchecked Sendable {
        var detail: CoreHTTPExchangeDetail?
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// The log's revision, which changes whenever an exchange is recorded or the log is cleared.
    ///
    /// - Returns: The revision, or zero when the core is closed.
    public func revision() -> UInt64 {
        chiaki_bridge.HttpCallsBridge.revision()
    }

    /// The whole log.
    ///
    /// - Returns: The tallies and every exchange, newest first.
    /// - Throws: ``Closed`` when the core is not open.
    public func log() async throws(Closed) -> CoreHTTPLog {
        let log = await Task.detached(priority: .utility) {
            let collector = LogCollector()
            let totals = withExtendedLifetime(collector) {
                chiaki_bridge.HttpCallsBridge.calls(
                    { call, context in
                        guard let call, let context else {
                            return
                        }
                        Unmanaged<LogCollector>.fromOpaque(context).takeUnretainedValue().exchanges
                            .append(HTTPCallsBridge.exchange(of: call.pointee))
                    },
                    Unmanaged.passUnretained(collector).toOpaque()
                ).value
            }
            return totals.map { totals in
                CoreHTTPLog(
                    revision: totals.revision,
                    totals: Self.totals(of: totals),
                    exchanges: collector.exchanges
                )
            }
        }.value
        guard let log else {
            throw Closed()
        }
        return log
    }

    /// The headers and bodies of one exchange.
    ///
    /// - Parameter exchange: The exchange's sequence number.
    /// - Returns: The detail, or `nil` when the log no longer holds the exchange or the core is closed.
    public func detail(of exchange: UInt64) async -> CoreHTTPExchangeDetail? {
        await Task.detached(priority: .utility) {
            let collector = DetailCollector()
            let found = withExtendedLifetime(collector) {
                chiaki_bridge.HttpCallsBridge.detail(
                    exchange,
                    { detail, context in
                        guard let detail, let context else {
                            return
                        }
                        Unmanaged<DetailCollector>.fromOpaque(context).takeUnretainedValue()
                            .detail = HTTPCallsBridge.detail(of: detail.pointee)
                    },
                    Unmanaged.passUnretained(collector).toOpaque()
                )
            }
            return found
                ? collector.detail
                : nil
        }.value
    }

    /// Forgets every recorded exchange, keeping the tallies.
    public func clear() {
        chiaki_bridge.HttpCallsBridge.clear()
    }

    /// Sets every tally back to zero.
    public func resetTotals() {
        chiaki_bridge.HttpCallsBridge.reset_totals()
    }

    /// Closes every pooled connection, so the next request opens a fresh one.
    ///
    /// - Parameter reason: Why, for the log.
    public func dropConnections(because reason: String) {
        chiaki_bridge.HttpCallsBridge.drop_connections(std.string(reason))
    }

    /// The model exchange of the view the core lent.
    ///
    /// - Parameter call: What the core lent, valid only during the call.
    /// - Returns: The exchange.
    static func exchange(of call: chiaki_bridge.HttpCallView) -> CoreHTTPExchange {
        CoreHTTPExchange(
            id: call.sequence,
            area: area(of: call.area),
            credentials: Set(call.credentials.map(credential(of:))),
            credentialLabel: String(call.credential_label),
            label: String(call.label),
            attempt: Int(call.attempt),
            method: String(call.method),
            startedAt: CatalogBridge.date(of: call.started_at_ms),
            duration: .microseconds(call.duration_us),
            base: String(call.base),
            url: marked(of: call.url),
            status: call.status.value.map { Int($0) },
            reason: String(call.reason),
            transportError: call.transport_error.value.map(transportError(of:)),
            failed: call.failed,
            bytesSent: Int(clamping: call.bytes_sent),
            bytesReceived: Int(clamping: call.bytes_received)
        )
    }

    /// The model detail of the view the core lent.
    ///
    /// - Parameter detail: What the core lent, valid only during the call.
    /// - Returns: The detail.
    static func detail(of detail: chiaki_bridge.HttpCallDetailView) -> CoreHTTPExchangeDetail {
        CoreHTTPExchangeDetail(
            requestHeaders: detail.request_headers.map(header(of:)),
            requestBody: body(of: detail.request_body),
            responseHeaders: detail.response_headers.map(header(of:)),
            responseBody: body(of: detail.response_body)
        )
    }

    /// The model totals of the facts the core reported, with every credential present.
    ///
    /// - Parameter totals: What the core reported.
    /// - Returns: The totals.
    static func totals(of totals: chiaki_bridge.HttpTotalsFacts) -> CoreHTTPTotals {
        var credentials = Dictionary(uniqueKeysWithValues: CoreHTTPCredential.allCases.map { (
            $0,
            CoreHTTPTally()
        ) })
        for kind in totals.credentials {
            credentials[credential(of: kind.credential)] = tally(of: kind.tally)
        }
        var bases: [String: CoreHTTPTally] = [:]
        for base in totals.bases {
            bases[String(base.base)] = tally(of: base.tally)
        }
        return CoreHTTPTotals(
            all: tally(of: totals.all),
            anonymous: tally(of: totals.anonymous),
            credentials: credentials,
            bases: bases
        )
    }

    /// The model marked text of the view the core lent, copying the bytes once.
    ///
    /// - Parameter text: What the core lent.
    /// - Returns: The marked text.
    static func marked(of text: chiaki_bridge.MarkedTextView) -> CoreHTTPMarkedText {
        let bytes = text.text.map { Array(UnsafeBufferPointer(start: $0, count: text.size)) } ?? []
        return CoreHTTPMarkedText(bytes: bytes, spans: text.spans.map { span in
            CoreHTTPSecretSpan(
                offset: Int(span.offset),
                length: Int(span.length),
                kind: secretKind(of: span.kind)
            )
        })
    }

    /// The model header of the view the core lent.
    ///
    /// - Parameter header: What the core lent.
    /// - Returns: The header.
    static func header(of header: chiaki_bridge.HttpHeaderView) -> CoreHTTPHeader {
        CoreHTTPHeader(name: String(header.name), value: marked(of: header.value))
    }

    /// The model body of the view the core lent.
    ///
    /// - Parameter body: What the core lent.
    /// - Returns: The body.
    static func body(of body: chiaki_bridge.HttpBodyView) -> CoreHTTPBody {
        CoreHTTPBody(
            size: Int(clamping: body.size),
            kept: Int(clamping: body.kept),
            truncated: body.truncated,
            binary: body.binary,
            text: marked(of: body.text)
        )
    }

    /// The model tally of the core's.
    ///
    /// - Parameter tally: The core's tally.
    /// - Returns: The model tally.
    static func tally(of tally: chiaki_bridge.HttpTallyFacts) -> CoreHTTPTally {
        CoreHTTPTally(
            requests: Int(clamping: tally.requests),
            httpErrors: Int(clamping: tally.http_errors),
            transportErrors: Int(clamping: tally.transport_errors),
            bytesSent: Int(clamping: tally.bytes_sent),
            bytesReceived: Int(clamping: tally.bytes_received)
        )
    }

    /// The model area of the core's.
    ///
    /// - Parameter area: The core's area.
    /// - Returns: The model area.
    static func area(of area: libchiaking.diagnostics.HttpArea) -> CoreHTTPArea {
        switch area {
        case .users:
            .users
        case .consoles:
            .consoles
        case .catalog:
            .catalog
        case .trophies:
            .trophies
        case .messages:
            .messages
        case .play:
            .play
        case .other:
            .other
        }
    }

    /// The model credential of the core's.
    ///
    /// - Parameter credential: The core's credential.
    /// - Returns: The model credential.
    static func credential(of credential: libchiaking.platform.HttpCredential) -> CoreHTTPCredential {
        switch credential {
        case .account_token:
            .accountToken
        case .sign_in_cookie:
            .signInCookie
        case .gk_session:
            .gkSession
        case .client_credentials:
            .clientCredentials
        case .store_session:
            .storeSession
        case .sign_in_grant:
            .signInGrant
        }
    }

    /// The model secret kind of the core's.
    ///
    /// - Parameter kind: The core's kind.
    /// - Returns: The model kind.
    static func secretKind(of kind: libchiaking.diagnostics.HttpSecretKind) -> CoreHTTPSecretKind {
        switch kind {
        case .credential:
            .credential
        case .cookie:
            .cookie
        case .session:
            .session
        case .parameter:
            .parameter
        case .field:
            .field
        case .body:
            .body
        }
    }

    /// The model transport error of the core's.
    ///
    /// - Parameter error: The core's error.
    /// - Returns: The model error.
    static func transportError(of error: libchiaking.platform.HttpError) -> CoreHTTPTransportError {
        switch error {
        case .cancelled:
            .cancelled
        case .timed_out:
            .timedOut
        case .invalid_url:
            .invalidURL
        case .tls_trust_failed:
            .tlsTrustFailed
        case .proxy_failed:
            .proxyFailed
        case .disconnected:
            .disconnected
        case .response_too_large:
            .responseTooLarge
        case .unsupported:
            .unsupported
        case .backend_failure:
            .backendFailure
        }
    }
}
