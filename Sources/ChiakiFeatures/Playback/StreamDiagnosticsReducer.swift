import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Feature that samples stream statistics into telemetry and history, and owns the overlay appearance and
/// video analysis mode.
@Reducer public struct StreamDiagnosticsReducer {
    /// Lifecycle of the saved appearance, tagged so a stale load cannot overwrite a newer selection.
    public enum Preferences: Equatable, Sendable {
        /// The saved appearance has not been requested yet.
        case unloaded
        /// A load identified by the associated ID is in flight.
        case loading(UUID)
        /// The appearance is settled, either loaded from storage or changed by the user.
        case loaded
    }

    /// Whether the statistics sampling effect is active.
    public enum Sampling: Equatable, Sendable {
        /// No sampling effect is running.
        case stopped
        /// The sampling run identified by the associated ID is active; samples from other runs are ignored.
        case running(UUID)
    }

    /// Appearance, sampling state and the telemetry derived from the most recent statistics samples.
    @ObservableState public struct State: Equatable {
        /// Detail level, glass and layout the overlay is shown with.
        public var appearance = StreamDiagnosticsAppearance()
        /// Progress of loading the saved appearance.
        public var preferences = Preferences.unloaded
        /// Progress of the statistics sampling run.
        public var sampling = Sampling.stopped
        /// Video analysis mode currently applied to the player.
        public var analysis = StreamVideoAnalysisMode.off
        /// Turns raw statistics samples into telemetry with rates computed between samples.
        public var sampler = StreamTelemetrySampler()
        /// Telemetry computed from the latest sample.
        public var telemetry = StreamTelemetry()
        /// Rolling window of recent telemetry and event marks shown as sparklines and the event strip.
        public var history = StreamDiagnosticsHistory()
        /// Tracks sustained packet loss while the overlay is hidden so a warning can be raised.
        public var lossWarning = PacketLossWarning()

        /// Creates a state with the default appearance and nothing loaded or sampling.
        public init() {
        }

        /// Detail level of the current appearance.
        public var level: StreamDiagnosticsAppearance.Level {
            appearance.level
        }

        /// Whether the renderer measures light: while the overlay or a video analysis shows.
        public var measuresLight: Bool {
            appearance.level != .off || analysis != .off
        }
    }

    /// Events handled by ``StreamDiagnosticsReducer``.
    public enum Action: Equatable, Sendable {
        /// Starts a new sampling run, resetting telemetry, and loads the saved appearance if it has not been
        /// requested.
        case task
        /// Delivers a statistics sample tagged with the sampling run that produced it.
        case sampled(UUID, StreamStatisticsSample)
        /// Delivers the saved appearance for the load identified by the ID.
        case appearanceLoaded(UUID, StreamDiagnosticsAppearance)
        /// Reports that the load identified by the ID failed, keeping the current appearance.
        case appearanceLoadFailed(UUID)
        /// Reports that saving the appearance failed, with the formatted error to log.
        case appearanceSaveFailed(String)
        /// Sets the detail level and saves the appearance.
        case selectLevel(StreamDiagnosticsAppearance.Level)
        /// Sets the glass style and saves the appearance.
        case selectGlass(StreamDiagnosticsAppearance.Glass)
        /// Sets the sheet or floating layout and saves the appearance.
        case selectLayout(StreamDiagnosticsAppearance.Layout)
        /// Advances to the next shown detail level and saves the appearance.
        case cycleLevel
        /// Advances to the next glass style and saves the appearance.
        case cycleGlass
        /// Applies a video analysis mode to the player when it differs from the current one.
        case selectAnalysis(StreamVideoAnalysisMode)
    }

    /// Identifiers for the cancellable sampling and save effects.
    public enum CancelID: Sendable {
        /// The long-running statistics sampling effect.
        case sampling
        /// The most recent appearance save, cancelled when a newer save starts.
        case save
    }

    /// Client that samples statistics, applies video analysis and persists the appearance.
    @Dependency(\.streamSession) var client
    /// Logger that records appearance save failures.
    @Dependency(\.logger) var logger
    /// Generates the IDs that tag sampling runs and appearance loads.
    @Dependency(\.uuid) var uuid

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return start(&state)
            case let .sampled(id, sample):
                guard state.sampling == .running(id) else {
                    return .none
                }
                record(sample, into: &state)
                return .none
            case let .appearanceLoaded(id, appearance):
                guard state.preferences == .loading(id) else {
                    return .none
                }
                state.preferences = .loaded
                state.appearance = appearance
                return .none
            case let .appearanceLoadFailed(id):
                guard state.preferences == .loading(id) else {
                    return .none
                }
                state.preferences = .loaded
                return .none
            case let .appearanceSaveFailed(message):
                return .run { [logger] _ in
                    await logger.log(.diagnostic(
                        .playback, .warning,
                        "Stream diagnostics appearance could not be saved (\(message))"
                    ))
                }
            case let .selectLevel(level):
                return update(&state) {
                    $0.level = level
                }
            case let .selectGlass(glass):
                return update(&state) {
                    $0.glass = glass
                }
            case let .selectLayout(layout):
                return update(&state) {
                    $0.layout = layout
                }
            case .cycleLevel:
                return update(&state) {
                    $0.level = $0.level.nextShown
                }
            case .cycleGlass:
                return update(&state) {
                    $0.glass = $0.glass.next
                }
            case let .selectAnalysis(mode):
                guard state.analysis != mode else {
                    return .none
                }
                state.analysis = mode
                return .run { @MainActor [client] _ in
                    client.applyVideoAnalysis(mode)
                }
            }
        }
        .onChange(of: \.measuresLight) { _, measures in
            Reduce { _, _ in
                .run { @MainActor [client] _ in
                    client.measureLight(measures)
                }
            }
        }
    }

    private func start(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.sampling = .running(id)
        state.sampler = StreamTelemetrySampler()
        state.telemetry = StreamTelemetry()
        state.history.reset()
        state.lossWarning.reset()
        state.analysis = .off
        var effects: [Effect<Action>] = [
            .run { [client] send in
                for await sample in client.statisticsSamples() {
                    await send(.sampled(id, sample))
                }
            }
            .cancellable(id: CancelID.sampling, cancelInFlight: true)
        ]
        if state.preferences == .unloaded {
            let load = uuid()
            state.preferences = .loading(load)
            effects.append(.run { [client] send in
                do {
                    await send(.appearanceLoaded(load, try await client.loadDiagnosticsAppearance()))
                } catch {
                    await send(.appearanceLoadFailed(load))
                }
            })
        }
        return .merge(effects)
    }

    private func record(_ sample: StreamStatisticsSample, into state: inout State) {
        let telemetry = state.sampler.update(sample)
        state.telemetry = telemetry
        state.history.append(telemetry)
        if state.level.visible {
            state.lossWarning.reset()
        } else {
            state.lossWarning.sample(telemetry.packetLossPercent)
        }
    }

    private func update(
        _ state: inout State,
        _ change: (inout StreamDiagnosticsAppearance) -> Void
    ) -> Effect<Action> {
        var appearance = state.appearance
        change(&appearance)
        guard appearance != state.appearance else {
            return .none
        }
        state.appearance = appearance
        state.preferences = .loaded
        if appearance.level.visible {
            state.lossWarning.reset()
        }
        return .run { [client, appearance] send in
            do {
                try await client.saveDiagnosticsAppearance(appearance)
            } catch {
                await send(.appearanceSaveFailed(LogFormat.error(error)))
            }
        }
        .cancellable(id: CancelID.save, cancelInFlight: true)
    }
}
