import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import Foundation

extension NetworkClient {
    /// The client over the core, with console addresses classified and resolved by ``ConsoleNetworkLocality``
    /// and requests sent on one ephemeral session with cookies and caching turned off, which never follows a
    /// redirect and reads each body incrementally.
    public static var live: Self {
        let bridge = NatTypeBridge()
        let session = ephemeralSession()
        return Self(
            natType: { () throws(NatTypeFailure) in
                try await bridge.natType()
            },
            literalIsLocal: { address in
                ConsoleNetworkLocality.isLocal(literal: address)
            },
            consoleIsLocal: { address in
                await ConsoleNetworkLocality.isLocal(address)
            },
            send: { request, maximumBytes in
                try await Self.send(request, maximumBytes: maximumBytes, on: session)
            }
        )
    }

    private static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(
            configuration: configuration,
            delegate: RedirectRefusal(),
            delegateQueue: nil
        )
    }

    private static func send(
        _ request: URLRequest,
        maximumBytes: Int,
        on session: URLSession
    ) async throws -> HTTPResponse {
        guard maximumBytes > 0 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer {
            bytes.task.cancel()
        }
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            body.append(byte)
        }
        try Task.checkCancellation()
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String, let value = field.value as? String {
                result[key] = value
            }
        }
        return HTTPResponse(status: response.statusCode, headers: headers, body: body)
    }

    private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
