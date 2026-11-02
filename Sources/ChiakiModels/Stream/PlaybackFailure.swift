/// Why a console stream could not start or ended early.
public enum PlaybackFailure: Error, Equatable, Sendable {
    /// The saved pairing failed to load, the console left the account, Remote Play is disabled for it, the
    /// controller settings failed to load, or the video surface could not be created.
    case credentials, remoteUnavailable, remoteDisabled, inputConfiguration, renderer
    /// The console has not been discovered on the local network yet.
    case consoleNotOnLocalNetwork
    /// The wake request could not be sent.
    case wakeRefused
    /// The stream was refused or ended with an outcome, noting whether it ran over the internet.
    case stream(StreamOutcome, overInternet: Bool)

    /// The refusal returned while the previous stream is still closing.
    public static let busy = Self.stream(.startRefused(.busy), overInternet: false)

    /// The stream outcome when this is a stream failure, otherwise `nil`.
    public var outcome: StreamOutcome? {
        guard case .stream(let outcome, _) = self else {
            return nil
        }
        return outcome
    }

    /// Whether the console rejected the saved pairing, so the player must pair again.
    public var rejectsPairing: Bool {
        outcome?.cause == .pairingRejected
    }
}
