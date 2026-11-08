import Foundation

/// The stream microphone's state machine: permission, connection, live and muted, and failure.
///
/// Every asynchronous completion carries the capture id that started it, so a late answer for an abandoned
/// attempt changes nothing. ``handle(_:)`` returns the commands the caller must carry out.
public struct MicrophoneMachine: Equatable, Sendable {
    /// Where the microphone is.
    public enum Phase: Equatable, Sendable {
        /// Off.
        case off

        /// Waiting for the user to grant microphone access for the capture id.
        case requestingPermission(UUID)

        /// The user refused microphone access.
        case denied

        /// Capture is starting for the id.
        case connecting(UUID)

        /// Capture is running for the id, muted or not.
        case live(UUID, muted: Bool)

        /// The microphone stopped for the reason given.
        case failed(MicrophoneFailure)

        /// The capture id that holds the input device, if any.
        public var capture: UUID? {
            switch self {
            case .connecting(let id), .live(let id, _):
                id
            case .off, .requestingPermission, .denied, .failed:
                nil
            }
        }

        /// Whether audio is being sent to the console.
        public var transmitting: Bool {
            if case .live(_, muted: false) = self {
                return true
            }
            return false
        }
    }

    /// Something that happened to the microphone.
    public enum Event: Equatable, Sendable {
        /// The user pressed the microphone button; the id names a new attempt.
        case toggle(UUID)

        /// The permission answer for an attempt.
        case permission(UUID, granted: Bool)

        /// Capture started for an attempt.
        case connected(UUID)

        /// Capture failed for an attempt.
        case failed(UUID, MicrophoneFailure)

        /// A mute change was applied, or failed, for an attempt.
        case muteApplied(UUID, muted: Bool, failure: MicrophoneFailure?)

        /// The stream ended; everything stops.
        case reset
    }

    /// Work the caller must carry out after an event.
    public enum Command: Equatable, Sendable {
        /// Ask for microphone access for an attempt.
        case requestPermission(UUID)

        /// Start capture for an attempt.
        case startCapture(UUID)

        /// Stop capture for an attempt.
        case stopCapture(UUID)

        /// Mute or unmute an attempt's capture.
        case setMuted(UUID, Bool)
    }

    /// The current phase.
    public private(set) var phase = Phase.off

    /// Creates a machine.
    ///
    /// - Parameter phase: The starting phase.
    public init(phase: Phase = .off) {
        self.phase = phase
    }

    /// Whether audio is being sent to the console.
    public var transmitting: Bool {
        phase.transmitting
    }

    /// Applies an event.
    ///
    /// - Parameter event: What happened.
    /// - Returns: The commands to carry out, in order.
    public mutating func handle(_ event: Event) -> [Command] {
        switch event {
        case .toggle(let id):
            toggle(id)
        case let .permission(id, granted):
            permission(id, granted: granted)
        case .connected(let id):
            connected(id)
        case let .failed(id, failure):
            failed(id, failure)
        case let .muteApplied(id, muted, failure):
            muteApplied(id, muted: muted, failure: failure)
        case .reset:
            reset()
        }
    }

    private mutating func toggle(_ id: UUID) -> [Command] {
        switch phase {
        case .off, .denied, .failed:
            phase = .requestingPermission(id)
            return [.requestPermission(id)]
        case .requestingPermission:
            phase = .off
            return []
        case .connecting(let current):
            phase = .off
            return [.stopCapture(current)]
        case let .live(current, muted):
            phase = .live(current, muted: !muted)
            return [.setMuted(current, !muted)]
        }
    }

    private mutating func permission(_ id: UUID, granted: Bool) -> [Command] {
        guard phase == .requestingPermission(id) else {
            return []
        }
        guard granted else {
            phase = .denied
            return []
        }
        phase = .connecting(id)
        return [.startCapture(id)]
    }

    private mutating func connected(_ id: UUID) -> [Command] {
        guard phase == .connecting(id) else {
            return []
        }
        phase = .live(id, muted: false)
        return []
    }

    private mutating func failed(_ id: UUID, _ failure: MicrophoneFailure) -> [Command] {
        guard capturing(id) else {
            return []
        }
        phase = .failed(failure)
        return [.stopCapture(id)]
    }

    private mutating func muteApplied(_ id: UUID, muted: Bool, failure: MicrophoneFailure?) -> [Command] {
        guard let failure, phase == .live(id, muted: muted) else {
            return []
        }
        phase = .failed(failure)
        return [.stopCapture(id)]
    }

    private mutating func reset() -> [Command] {
        let active = phase.capture
        phase = .off
        return active.map {
            [.stopCapture($0)]
        } ?? []
    }

    private func capturing(_ id: UUID) -> Bool {
        phase.capture == id
    }
}

/// Why the stream microphone stopped or could not start.
public enum MicrophoneFailure: Equatable, Sendable {
    /// No stream is running to send audio to.
    case streamUnavailable

    /// The input device could not be opened, with the explanation shown to the user.
    case captureUnavailable(LocalizedStringResource)

    /// The console refused microphone audio.
    case consoleRejected

    /// Capture stopped unexpectedly, with the explanation shown to the user.
    case interrupted(LocalizedStringResource)

    /// No microphone input exists.
    public static let noInput = MicrophoneFailure.captureUnavailable(.streamMicrophoneNoInput)

    /// The audio encoder for the microphone could not be created.
    public static let encoderFailed = MicrophoneFailure.captureUnavailable(.streamMicrophoneEncoderFailed)

    /// The console never answered the request to open the microphone.
    public static let noAnswer = MicrophoneFailure.interrupted(.streamMicrophoneNoAnswer)

    /// The input device changed or went away while capturing.
    public static let inputChanged = MicrophoneFailure.interrupted(.streamMicrophoneInputChanged)

    /// The capture engine could not start.
    ///
    /// - Parameter reason: The system's reason, in its own words.
    /// - Returns: The failure.
    public static func startFailed(_ reason: String) -> MicrophoneFailure {
        .captureUnavailable(.streamMicrophoneStartFailed(reason: reason))
    }

    /// The capture engine stopped and could not restart.
    ///
    /// - Parameter reason: The system's reason, in its own words.
    /// - Returns: The failure.
    public static func stopped(_ reason: String) -> MicrophoneFailure {
        .interrupted(.streamMicrophoneStopped(reason: reason))
    }
}

/// How captured microphone audio is processed before it is sent.
public enum MicrophoneProcessing: Equatable, Sendable {
    /// Voice processing with echo cancellation and noise suppression.
    case voice

    /// The input unprocessed.
    case raw
}

/// A progress event from a microphone capture operation.
public enum MicrophoneCaptureEvent: Equatable, Sendable {
    /// Capture is running and audio is reaching the stream.
    case started
    /// Capture could not start or stopped with the given failure.
    case failed(MicrophoneFailure)
}
