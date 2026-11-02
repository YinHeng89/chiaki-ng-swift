import ChiakiBridge
import ChiakiModels

/// How a guest's run of a shared stream ended.
public enum KakusanGuestEnd: Equatable, Sendable {
    /// The run ended normally.
    case finished

    /// The run was cancelled.
    case cancelled

    /// The run failed.
    case failed(KakusanError)

    /// Reads how the core says the run ended.
    ///
    /// - Parameter outcome: What the core reported.
    public init(_ outcome: chiaki_bridge.GuestOutcome) {
        switch outcome.kind() {
        case .ended:
            self.init(end: outcome.ending())
        case .declined:
            self = .failed(KakusanCommandReader.error(of: outcome.decline()))
        case .refused:
            self = .failed(Self.error(of: outcome.refusal()))
        }
    }

    /// Reads how a run that started ended.
    ///
    /// - Parameter end: What the core reported.
    init(end: chiaki_bridge.GuestEndFacts) {
        if let refused = end.refused.value {
            self = .failed(KakusanCommandReader.error(of: refused))
            return
        }
        if end.media_failure.value != nil {
            self = .failed(.codec)
            return
        }
        switch end.status {
        case .completed:
            self = .finished
        case .cancelled:
            self = .cancelled
        case .media_failed:
            self = .failed(.codec)
        case .visit_failed:
            self = .failed(.internal)
        }
    }

    /// Throws the failure, if the run failed.
    ///
    /// - Throws: The `ChiakiModels/KakusanError` the run failed with.
    public func resolve() throws(KakusanError) {
        if case .failed(let error) = self {
            throw error
        }
    }

    private static func error(of refusal: chiaki_bridge.StreamRefusal) -> KakusanError {
        switch refusal {
        case .core_closed:
            .cryptoUnavailable
        case .unknown_user, .unknown_console, .invalid_title, .no_decoder:
            .internal
        }
    }
}
