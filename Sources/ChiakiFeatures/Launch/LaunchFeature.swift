import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus
import SwiftUI

/// Runs a stream asked for on the command line or by a file: finds the console, connects, shows the stream
/// the way it was asked for and quits afterwards when asked to.
///
/// The workflow is ``LaunchFlow``; this feature performs its effects. It never writes another feature's state:
/// the parent reports the consoles and the stream activity it observes, and the feature asks the parent to
/// connect or to hand the window back through ``Action/Delegate``. A failure is shown as an alert.
@Reducer public struct LaunchFeature {
    /// The launch's state.
    @ObservableState public struct State: Equatable {
        /// The launch workflow.
        public var flow = LaunchFlow()
        /// Why the last launch failed, shown until it is dismissed.
        @Presents public var notice: AlertState<Never>?

        /// Creates an idle launch.
        public init() {
        }
    }

    /// What the launch can do.
    public enum Action: Equatable {
        /// A stream was asked for while the consoles and the stream activity were as given.
        case requested(LaunchRequest, LaunchFlow.Consoles, LaunchFlow.StreamActivity)
        /// The saved consoles changed.
        case consolesChanged(LaunchFlow.Consoles)
        /// The stream activity changed.
        case streamChanged(LaunchFlow.StreamActivity)
        /// The connect with this id was rejected.
        case connectRejected(UUID, LaunchRejection)
        /// The wait for the launch with this id ran out.
        case timedOut(UUID)
        /// The failure notice was dismissed.
        case notice(PresentationAction<Never>)
        /// Asks the parent to act for the launch.
        case delegate(Delegate)

        /// What the launch asks its parent to do.
        @CasePathable public enum Delegate: Equatable, Sendable {
            /// Connect to this console; the launch owns the window until the stream ends.
            case connect(LaunchConnect)
            /// The stream owns the window again.
            case releaseWindow
        }
    }

    /// How long a launch may take to start streaming.
    public static let timeout: Duration = .seconds(45)

    /// How long a connect may take before the launch gives up.
    public static let connectTimeout: Duration = .seconds(15)

    @Dependency(\.platform) private var client
    @Dependency(\.logger) private var logger
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.uuid) private var uuid

    private enum CancelID {
        case timeout
        case connect
    }

    /// Creates the feature.
    public init() {
    }

    /// Runs the launch.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .requested(request, consoles, activity):
                return send(.requested(uuid(), request, consoles, activity), state: &state)
            case .consolesChanged(let consoles):
                return observe(.consolesChanged(consoles), state: &state)
            case .streamChanged(let activity):
                return observe(.stream(activity), state: &state)
            case let .connectRejected(id, reason):
                return send(.connectRejected(id, reason), state: &state)
            case .timedOut(let id):
                return send(.timedOut(id), state: &state)
            case .notice, .delegate:
                return .none
            }
        }
        .ifLet(\.$notice, action: \.notice)
    }

    /// Feeds a change the root observed, in the consoles or the stream, into the launch flow.
    ///
    /// The root calls this directly whenever the consoles or the stream change, so a waiting launch moves on in
    /// the same reduction.
    ///
    /// - Parameters:
    ///   - event: The observed change.
    ///   - state: The launch's state.
    /// - Returns: The effects the flow asks for.
    public func observe(_ event: LaunchFlow.Event, state: inout State) -> Effect<Action> {
        send(event, state: &state)
    }

    private func send(_ event: LaunchFlow.Event, state: inout State) -> Effect<Action> {
        let effects = state.flow.send(event)
        guard !effects.isEmpty else {
            return .none
        }
        let performed: Effect<Action> = .merge(effects.filter { $0 != .quit }.map { effect in
            perform(effect, state: &state)
        })
        guard effects.contains(.quit) else {
            return performed
        }
        return .concatenate(performed, perform(.quit, state: &state))
    }

    private func timeout(_ id: UUID, after delay: Duration) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: delay)
            await send(.timedOut(id))
        }
        .cancellable(id: CancelID.timeout, cancelInFlight: true)
    }

    private func perform(_ effect: LaunchFlow.Effect, state: inout State) -> Effect<Action> {
        switch effect {
        case let .connect(request, display):
            return .concatenate(
                .run { [client] _ in
                    await client.prepareLaunch(display)
                },
                .send(.delegate(.connect(request)))
            )
            .cancellable(id: CancelID.connect, cancelInFlight: true)
        case .present(let display):
            return .run { [client] _ in
                await client.presentLaunch(display)
            }
        case .scheduleTimeout(let id):
            return timeout(id, after: Self.timeout)
        case .scheduleConnectTimeout(let id):
            return timeout(id, after: Self.connectTimeout)
        case .cancelTimeout:
            return .cancel(id: CancelID.timeout)
        case .cancelConnect:
            return .cancel(id: CancelID.connect)
        case .restoreDisplay:
            return .merge(
                .send(.delegate(.releaseWindow)),
                .run { [client] _ in
                    await client.restoreLaunch()
                }
            )
        case .quit:
            return .run { [client, logger] _ in
                await logger.log(.diagnostic(
                    .app, .info,
                    "Quitting for --exit-app-on-stream-exit because the requested stream ended or couldn’t start"
                ))
                await client.quit()
            }
        case .report(let failure):
            state.notice = Self.notice(failure)
            return .run { [logger] _ in
                await logger.log(.diagnostic(.app, .warning, failure.logDescription))
            }
        }
    }

    /// The alert that explains a failed launch.
    ///
    /// - Parameter failure: Why the launch failed.
    /// - Returns: An alert with the failure's title and message and an OK button.
    public static func notice(_ failure: LaunchFailure) -> AlertState<Never> {
        AlertState {
            TextState(failure.title)
        } actions: {
            ButtonState(role: .cancel) {
                TextState(.commonOk)
            }
        } message: {
            TextState(failure.message)
        }
    }
}

/// Shows why a launch asked for on the command line failed.
public struct LaunchNoticePresentation: ViewModifier {
    /// The launch whose notice is shown.
    public let store: StoreOf<LaunchFeature>

    /// Shows the notice over the content until it is dismissed.
    ///
    /// - Parameter content: The view the notice covers.
    /// - Returns: The content with the notice.
    public func body(content: Content) -> some View {
        content.appConfirmation(store.notice.map(Self.confirmation)) {
            store.send(.notice(.dismiss))
        }
    }

    /// Turns the notice into the app's confirmation card.
    ///
    /// - Parameter notice: The launch's failure alert.
    /// - Returns: A card with the alert's title, message and OK button.
    public static func confirmation(_ notice: AlertState<Never>) -> AppConfirmation {
        AppConfirmation(
            title: .verbatim(String(state: notice.title)),
            message: notice.message.map { .verbatim(String(state: $0)) },
            systemImage: "exclamationmark.triangle",
            cancelTitle: .commonOk
        )
    }
}

extension View {
    /// Shows the launch's failure notice.
    ///
    /// - Parameter store: The launch.
    /// - Returns: The view with the notice.
    public func launchNotice(_ store: StoreOf<LaunchFeature>) -> some View {
        modifier(LaunchNoticePresentation(store: store))
    }
}
