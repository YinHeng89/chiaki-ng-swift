import Foundation

/// A received HTTP response: its status code, headers and whole body.
public struct HTTPResponse: Equatable, Sendable {
    /// The HTTP status code.
    public let status: Int

    /// The response headers as the server sent them.
    public let headers: [String: String]

    /// The response body.
    public let body: Data

    /// Creates a response.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - headers: The response headers.
    ///   - body: The response body.
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Looks up a header by name, ignoring case.
    ///
    /// - Parameter name: The header name.
    /// - Returns: The header's value, or `nil` when it is absent.
    public func header(_ name: String) -> String? {
        headers.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}
