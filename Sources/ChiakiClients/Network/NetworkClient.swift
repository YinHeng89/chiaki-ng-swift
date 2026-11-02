import ChiakiModels
import Dependencies
import Foundation

/// Reaches the network: checks how this Mac reaches the internet, whether a console address is on the local
/// network, and sends the few HTTP requests the core does not make itself.
///
/// The live value, in `ChiakiClientsLive`, asks STUN servers through the core, resolves console names and sends
/// requests on an ephemeral session that keeps no cookies or cache and never follows a redirect, so a redirect
/// comes back as the response itself. The test value fails every check, knows no address literal, counts every
/// console as local and refuses every request.
public struct NetworkClient: Sendable {
    /// Finds this Mac's NAT type.
    public var natType: @Sendable () async throws(NatTypeFailure) -> NatType

    /// Classifies a literal IP address as local or not, or returns `nil` when the text is not an IP literal.
    public var literalIsLocal: @Sendable (_ address: String) -> Bool?

    /// Whether a console address or host name is on the local network, resolving names when needed.
    public var consoleIsLocal: @Sendable (_ address: String) async -> Bool

    /// Sends a request and reads the body, stopping as soon as it grows past a limit.
    ///
    /// The first argument is the request and the second the largest body accepted, which must be positive. It
    /// throws `URLError(.dataLengthExceedsMaximum)` when the body exceeds the limit, any transport error, or
    /// `CancellationError`.
    public var send: @Sendable (_ request: URLRequest, _ maximumBytes: Int) async throws -> HTTPResponse

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - natType: Finds the NAT type.
    ///   - literalIsLocal: Classifies a literal IP address.
    ///   - consoleIsLocal: Decides whether a console address or host name is local.
    ///   - send: Sends an HTTP request and reads a bounded body.
    public init(
        natType: @escaping @Sendable () async throws(NatTypeFailure) -> NatType,
        literalIsLocal: @escaping @Sendable (_ address: String) -> Bool? = { _ in
            nil
        },
        consoleIsLocal: @escaping @Sendable (_ address: String) async -> Bool = { _ in
            true
        },
        send: @escaping @Sendable (_ request: URLRequest, _ maximumBytes: Int) async throws
            -> HTTPResponse = { _, _ in
                throw URLError(.notConnectedToInternet)
            }
    ) {
        self.natType = natType
        self.literalIsLocal = literalIsLocal
        self.consoleIsLocal = consoleIsLocal
        self.send = send
    }
}

extension NetworkClient: TestDependencyKey {
    /// Fails every check, counts every console as local and refuses every request, so tests never reach the
    /// network.
    public static let testValue = Self(natType: { () throws(NatTypeFailure) in
        throw .network
    })
}

extension DependencyValues {
    /// Reaches the network.
    public var network: NetworkClient {
        get {
            self[NetworkClient.self]
        }
        set {
            self[NetworkClient.self] = newValue
        }
    }
}
