import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Launches a recently played title on a console and follows the stream that shows it.
///
/// The console is asked to launch the title; whatever it answers, the feature asks its parent to start the
/// stream with ``Action/Delegate/startStream(_:)``. When the console asks for its login passcode during the
/// stream, the launch is sent again once the stream connects. Each launch carries the
/// `ChiakiModels/OperationID` that started it.
@Reducer
public struct TitleLaunchFeature {
    /// Whether a login passcode interrupted the launched stream.
    public enum LoginPIN: Equatable, Sendable {
        /// No passcode was asked for.
        case none

        /// The console asked for the passcode.
        case requested

        /// The launch was sent again after the passcode.
        case resent
    }

    /// Where the launch is.
    @ObservableState
    public enum State: Equatable {
        /// No title is being launched.
        case idle

        /// The console is being asked to launch the title.
        case launching(OperationID, TitleLaunch)

        /// The launch was sent; the stream is starting.
        case awaitingStream(TitleLaunch)

        /// The stream for the launched title runs as this session.
        case streaming(UUID, TitleLaunch, LoginPIN)

        /// The title being launched or streamed.
        public var title: RecentTitle? {
            switch self {
            case .idle:
                nil
            case .launching(_, let launch), .awaitingStream(let launch), .streaming(_, let launch, _):
                launch.title
            }
        }
    }

    /// Everything the launch reacts to.
    public enum Action: Equatable, Sendable {
        /// Launches a title.
        case play(TitleLaunch)

        /// The console answered the launch with this id.
        case launchFinished(OperationID)

        /// Abandons the launch.
        case cancel

        /// The stream started as this session.
        case streamStarted(UUID)

        /// The stream with this session asked for the login passcode.
        case loginPINRequested(UUID)

        /// The stream with this session showed its first frame.
        case streamConnected(UUID)

        /// The stream ended.
        case streamEnded

        /// What the parent is told.
        case delegate(Delegate)

        /// What the launch reports to its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// The title was launched; start the stream.
            case startStream(TitleLaunch)
        }
    }

    private enum CancelID {
        case launch
    }

    @Dependency(\.consoles) private var client
    @Dependency(\.uuid) private var uuid
    @Dependency(\.logger) private var logger

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .play(let request):
                guard state == .idle else {
                    return .none
                }
                let id = OperationID(uuid: uuid())
                state = .launching(id, request)
                return launch(request, id: id)
            case .launchFinished(let id):
                guard case let .launching(current, request) = state, current == id else {
                    return .none
                }
                state = .awaitingStream(request)
                return .send(.delegate(.startStream(request)))
            case .cancel:
                state = .idle
                return .cancel(id: CancelID.launch)
            case .streamStarted(let session):
                guard case let .awaitingStream(request) = state else {
                    return .none
                }
                state = .streaming(session, request, .none)
                return .none
            case .loginPINRequested(let session):
                guard case let .streaming(current, request, .none) = state, current == session else {
                    return .none
                }
                state = .streaming(session, request, .requested)
                return .none
            case .streamConnected(let session):
                guard case let .streaming(current, request, .requested) = state, current == session else {
                    return .none
                }
                state = .streaming(session, request, .resent)
                return resend(request)
            case .streamEnded:
                guard state != .idle else {
                    return .none
                }
                state = .idle
                return .cancel(id: CancelID.launch)
            case .delegate:
                return .none
            }
        }
    }

    private func launch(_ request: TitleLaunch, id: OperationID) -> Effect<Action> {
        .run { [client, logger] send in
            do {
                let outcome = try await client.launchTitle(
                    request.accountID,
                    request.hardwareID,
                    request.title
                )
                await logger.log(.diagnostic(
                    .recentlyPlayed, .info,
                    "Launching \(request.title.titleID) answered \(outcome); starting the stream"
                ))
            } catch is CancellationError {
                return
            } catch {
                await logger.log(.diagnostic(
                    .recentlyPlayed, .warning,
                    "Launching \(request.title.titleID) failed (\(error)); starting the stream anyway"
                ))
            }
            guard !Task.isCancelled else {
                return
            }
            await send(.launchFinished(id))
        }
        .cancellable(id: CancelID.launch, cancelInFlight: true)
    }

    private func resend(_ request: TitleLaunch) -> Effect<Action> {
        .run { [client, logger] _ in
            let outcome: String
            do {
                let answer = try await client.launchTitle(
                    request.accountID,
                    request.hardwareID,
                    request.title
                )
                outcome = "\(answer)"
            } catch {
                outcome = "an error (\(error))"
            }
            await logger.log(.diagnostic(
                .recentlyPlayed, .info,
                "Resent the launch of \(request.title.titleID) after the login passcode; answered \(outcome)"
            ))
        }
    }
}
