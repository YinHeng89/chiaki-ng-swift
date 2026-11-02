import ChiakiModels

/// One thing worth writing to the log, with the level it is written at and its rendered text.
public enum LogEvent: Equatable, Sendable {
    /// The stream video was configured before starting.
    ///
    /// - Parameters:
    ///   - height: The requested vertical resolution in pixels.
    ///   - framesPerSecond: The requested frame rate.
    ///   - megabitsPerSecond: The requested bitrate.
    ///   - codec: The display name of the requested codec.
    ///   - dynamicRange: Whether HDR was requested and why not when it was not.
    case videoConfigured(
        height: Int, framesPerSecond: Int, megabitsPerSecond: Int, codec: String,
        dynamicRange: VideoDynamicRange
    )

    /// The console session setup reached a new stage.
    ///
    /// - Parameters:
    ///   - stage: The core's setup stage number.
    ///   - elapsedMilliseconds: Time since setup began.
    case remoteSetupProgress(stage: Int, elapsedMilliseconds: Int)

    /// The user stopped a cloud session while it was starting.
    case cloudPlaybackCancelled

    /// No video frame arrived in time and the attempt was abandoned.
    ///
    /// - Parameter attempt: The zero-based start attempt.
    case videoStartupTimedOut(attempt: Int)

    /// A line the native core wrote to its diagnostic queue.
    ///
    /// - Parameters:
    ///   - severity: The core's severity, 0 for errors through 3 and above for debug.
    ///   - message: The line as the core wrote it.
    case coreDiagnostic(severity: Int, message: String)

    /// The API capture file could not be written.
    case apiCaptureWriteFailed

    /// A controller step held the main thread long enough to delay input.
    ///
    /// - Parameters:
    ///   - step: The name of the step.
    ///   - milliseconds: How long it took.
    case slowControllerStep(step: String, milliseconds: Int)

    /// The first input from a controller reached the stream.
    ///
    /// - Parameters:
    ///   - player: The one-based player number.
    ///   - controller: The controller's name.
    case controllerInputReachedStream(player: Int, controller: String)

    /// A controller or input routing detail, described in the associated text.
    case controllerDiagnostic(String)

    /// A console lookup or launch detail, described in the associated text.
    case consoleDiagnostic(String)

    /// A console problem that did not stop the workflow, described in the associated text.
    case consoleWarning(String)

    /// A free-form line: the area writing it, the level to write it at and the text.
    case diagnostic(LogArea, LogLevel, String)

    /// The level the event is written at.
    public var level: LogLevel {
        switch self {
        case let .diagnostic(_, level, _):
            level
        case let .coreDiagnostic(severity, _):
            Self.level(coreSeverity: severity)
        case .apiCaptureWriteFailed, .videoStartupTimedOut:
            .error
        case .videoConfigured, .cloudPlaybackCancelled, .controllerDiagnostic, .consoleDiagnostic,
             .slowControllerStep, .controllerInputReachedStream:
            .info
        case .remoteSetupProgress:
            .debug
        case .consoleWarning:
            .warning
        }
    }

    /// The text written for the event.
    public var message: String {
        switch self {
        case let .diagnostic(area, _, text):
            "\(area.rawValue): \(text)"
        case .apiCaptureWriteFailed:
            "API capture could not be written. Check the Developer log folder."
        case let .coreDiagnostic(_, message):
            message
        case let .videoConfigured(height, framesPerSecond, megabitsPerSecond, codec, dynamicRange):
            "Video requested: \(height)p \(framesPerSecond) fps \(megabitsPerSecond) Mbps \(codec); "
                + dynamicRange.summary
        case let .remoteSetupProgress(stage, elapsed):
            "Remote setup: \(Self.setupStageNames[stage] ?? "Unknown stage") (stage=\(stage), elapsed=\(elapsed) ms)"
        case .cloudPlaybackCancelled:
            "Cloud: stop requested by the user; cancelling the cloud session"
        case let .videoStartupTimedOut(attempt):
            "Playback: no video frame within 75 s of start attempt \(attempt + 1); cancelling the "
                + "connection and showing the timeout to the user"
        case let .slowControllerStep(step, milliseconds):
            "Controller: Slow controller step: \(step) took \(milliseconds) ms on the main thread"
        case let .controllerInputReachedStream(player, controller):
            "Controller: player \(player) input from \"\(controller)\" reached the stream"
        case let .controllerDiagnostic(message):
            "Controller: \(message)"
        case let .consoleDiagnostic(message), let .consoleWarning(message):
            message
        }
    }

    private static func level(coreSeverity: Int) -> LogLevel {
        switch coreSeverity {
        case 0:
            .error
        case 1:
            .warning
        case 2:
            .info
        default:
            .debug
        }
    }

    private static let setupStageNames = [
        2: "Registration", 3: "Session initialization", 4: "Ctrl connection", 5: "Ctrl session identifier",
        6: "Ctrl features", 7: "Ctrl receive", 8: "Network calibration", 9: "Route switch",
        10: "Stream transport", 16: "PSN session creation", 17: "PSN console start",
        18: "Control route hole punching", 19: "Data route hole punching", 22: "Shutdown"
    ]
}

/// The part of the app a free-form log line comes from; the raw value prefixes the line.
public enum LogArea: String, Sendable {
    /// App lifecycle, windows and settings.
    case app = "App"

    /// PSN accounts and sign-in.
    case accounts = "Accounts"

    /// Searching the network for consoles.
    case discovery = "Discovery"

    /// Pairing with a console.
    case registration = "Registration"

    /// Console streaming.
    case playback = "Playback"

    /// Cloud streaming.
    case cloud = "Cloud"

    /// The cloud game catalog.
    case cloudLibrary = "Cloud library"

    /// Controllers and input.
    case controller = "Controller"

    /// The native core.
    case core = "Core"

    /// Recently played titles.
    case recentlyPlayed = "Recently played"

    /// Kakusan.
    case kakusan = "Kakusan"
}
