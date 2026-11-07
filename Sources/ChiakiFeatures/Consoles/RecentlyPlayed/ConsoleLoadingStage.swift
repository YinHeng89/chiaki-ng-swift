import ChiakiModels
import Foundation

/// What the loading screen shows while a title launches or a stream connects.
public enum ConsoleLoadingStage: Equatable {
    /// The console is launching the named title.
    case startingTitle(String)

    /// The stream connected and waits for its first frame.
    case waitingForVideo

    /// The stage a stream with this status shows, if any.
    ///
    /// - Parameters:
    ///   - status: The stream's status.
    ///   - title: The title being launched, if one is.
    /// - Returns: Waiting for video while the stream connects, the title launch while no stream runs and a
    ///   title launches, else `nil`.
    public init?(status: StreamStatus, launching title: RecentTitle?) {
        switch status {
        case .connecting:
            self = .waitingForVideo
        case .idle:
            guard let title else {
                return nil
            }
            self = .startingTitle(title.name)
        case .playing, .stopping, .failed:
            return nil
        }
    }

    /// The status line.
    public var status: LocalizedStringResource {
        switch self {
        case .startingTitle(let name):
            .consolesLoadingStartingTitle(title: name)
        case .waitingForVideo:
            .consolesLoadingWaitingForVideo
        }
    }

    /// The step of the loading indicator.
    public var step: Int {
        switch self {
        case .startingTitle:
            1
        case .waitingForVideo:
            2
        }
    }

    /// Which control cancelled the stage, for the stop trace.
    public var cancelledFrom: String {
        switch self {
        case .startingTitle:
            "the title launch screen's cancel"
        case .waitingForVideo:
            "the connecting screen's cancel"
        }
    }
}
