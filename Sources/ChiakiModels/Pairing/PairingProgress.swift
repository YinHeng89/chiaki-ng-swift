/// One report of how far a pairing attempt has got.
public struct PairingProgress: Hashable, Sendable {
    /// The step just entered.
    public let step: PairingStep

    /// Which attempt this is, counting from one.
    public let attempt: Int

    /// Time since the attempt began.
    public let elapsed: Duration

    /// What the attempt is waiting for, when it is waiting.
    public let wait: ProgressWait?

    /// Describes a report.
    ///
    /// - Parameters:
    ///   - step: The step just entered.
    ///   - attempt: Which attempt this is, counting from one.
    ///   - elapsed: Time since the attempt began.
    ///   - wait: What the attempt is waiting for, if anything.
    public init(step: PairingStep, attempt: Int = 1, elapsed: Duration = .zero, wait: ProgressWait? = nil) {
        self.step = step
        self.attempt = attempt
        self.elapsed = elapsed
        self.wait = wait
    }
}

/// The steps of a pairing attempt, at home or over the internet, in the order they occur.
public enum PairingStep: Hashable, Sendable, CaseIterable {
    /// The attempt has begun.
    case starting

    /// Internet pairing only: a PSN session is being opened.
    case openingAccountSession

    /// Internet pairing only: the console is being woken and asked to join.
    case wakingConsole

    /// A connection to the console is being opened.
    case reachingConsole

    /// The pairing request is being sent.
    case sendingRequest

    /// The request was sent and the console's answer is awaited.
    case waitingForAnswer

    /// The console accepted and the pairing is being saved.
    case saving
}
