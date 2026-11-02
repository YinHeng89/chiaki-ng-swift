import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Lists the consoles PSN holds for an account, through the open core.
///
/// The listing talks to PSN and blocks a core thread, so it runs on a dispatch queue while the calling task
/// waits; cancelling the task cancels the core request.
public struct AccountConsolesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The consoles of one generation on an account.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - kind: The generation to list.
    /// - Returns: The consoles PSN listed.
    /// - Throws: ``CoreUnanswered`` when PSN did not answer or the account is not one the core holds.
    public func consoles(of account: AccountID,
                         kind: ConsoleKind) async throws(CoreUnanswered) -> [PSNConsole] {
        let result = await CoreCancellation.run { request in
            Self.result(of: chiaki_bridge.AccountConsolesBridge.on_account(
                request, UsersBridge.vector(account), ConsoleFactsReader.generation(of: kind)
            ))
        }
        return try result.get()
    }

    /// The model result of an account console listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The consoles, or why PSN did not answer.
    static func result(of outcome: chiaki_bridge
        .AccountConsolesOutcome) -> Result<[PSNConsole], CoreUnanswered> {
        switch outcome.kind() {
        case .listed:
            return .success(outcome.consoles().map { console in
                PSNConsole(
                    deviceID: Data(Array(console.device_uid)),
                    name: String(console.name),
                    ps5: console.generation == .ps5,
                    remotePlayEnabled: console.remote_play_enabled
                )
            })
        case .unanswered:
            let unanswered = outcome.why_unanswered()
            return .failure(CoreUnanswered(
                reason: CoreUnanswered.reason(of: unanswered.reason),
                httpStatus: Int(unanswered.http_status)
            ))
        case .refused:
            return .failure(CoreUnanswered(
                reason: outcome.refusal() == .core_closed
                    ? .coreClosed
                    : .unknownUser
            ))
        }
    }
}
