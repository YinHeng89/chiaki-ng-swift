/// Why a pairing attempt did not produce a saved pairing.
public enum PairingFailure: Error, Hashable, Sendable {
    /// The address, PIN or account was rejected before anything was sent.
    case invalidInput

    /// The console refused the request or its reply could not be used. A wrong or expired PIN is the usual
    /// cause.
    case rejected

    /// The console did not answer or its address could not be reached.
    case unreachable

    /// Pairing is not available: the core is closed or lacks what pairing needs.
    case unavailable

    /// The console accepted but the pairing could not be saved.
    case notSaved

    /// Internet pairing was refused because a play session is running.
    case sessionPlaying

    /// The attempt was cancelled.
    case cancelled

    /// Pairing over the internet failed at a stage, with the HTTP status or console reason code when one was
    /// given.
    case overInternet(InternetPairingStage, code: Int?)

    /// Whether the failure came from pairing over the internet.
    public var isOverInternet: Bool {
        if case .overInternet = self {
            return true
        }
        return false
    }
}

/// How far pairing over the internet had got.
public enum InternetPairingStage: Hashable, Sendable, CaseIterable {
    /// The attempt had begun.
    case starting

    /// A PSN session for reaching the console was being opened.
    case openingSession

    /// The console was being woken through PSN.
    case wakingConsole

    /// A connection to the console was being established.
    case connecting

    /// The pairing exchange with the console was under way.
    case pairing
}
