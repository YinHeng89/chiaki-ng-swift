import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Foundation

/// Lists the consoles registered to a PlayStation Network account.
public struct PSNConsoleClient: Sendable {
    /// Lists an account's PS5 consoles when the flag is true, or its PS4 consoles otherwise, given the
    /// account ID bytes.
    public var list: @Sendable (Data, Bool) async throws -> [PSNConsole]
    /// Creates a client over a listing closure.
    ///
    /// - Parameter list: Lists consoles for account ID bytes and the PS5 flag.
    public init(list: @escaping @Sendable (Data, Bool) async throws -> [PSNConsole]) {
        self.list = list
    }
    /// The core-backed client, without logging.
    public static let live = logged(.disabled)
    /// A core-backed client that logs how long each listing took and why it failed.
    ///
    /// The client throws `RegistrationFailure/invalidInput` for malformed account bytes,
    /// `RegistrationFailure/remoteRejected` when sign-in is needed, `RegistrationFailure/unavailable` for
    /// other failures, and `CancellationError` when cancelled.
    ///
    /// - Parameter logger: Receives the diagnostics.
    /// - Returns: The client.
    public static func logged(_ logger: LoggerClient) -> Self {
        Self { account, ps5 in
            guard let account = AccountID(bytes: account) else {
                throw RegistrationFailure.invalidInput
            }
            let clock = ContinuousClock()
            let start = clock.now
            do throws(CoreUnanswered) {
                let consoles = try await AccountConsolesBridge().consoles(
                    of: account,
                    kind: ps5
                        ? .ps5
                        : .ps4
                )
                let kind = ps5
                    ? "PS5"
                    : "PS4"
                await logger.log(.diagnostic(
                    .registration, .info,
                    "PSN console list returned \(consoles.count) \(kind) console(s) in "
                        + "\(LogFormat.milliseconds(start.duration(to: clock.now))) ms"
                ))
                return consoles
            } catch {
                let failure = error
                if failure.reason == .cancelled {
                    throw CancellationError()
                }
                await logger.log(.diagnostic(
                    .registration, .warning,
                    "PSN console list failed after \(LogFormat.milliseconds(start.duration(to: clock.now))) ms: "
                        + "\(failure.reason), HTTP \(failure.httpStatus)"
                ))
                throw failure.needsSignIn
                    ? RegistrationFailure.remoteRejected
                    : RegistrationFailure.unavailable
            }
        }
    }
}
