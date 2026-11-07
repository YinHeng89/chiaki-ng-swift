import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Owns the in-stream menu: loading, live-tuning and saving picture and sound settings, controller navigation
/// between its levels, the leave confirmation and the diagnostics overlay.
@Reducer public struct StreamMenuReducer {
    /// Requests the menu sends to the stream that hosts it.
    public enum DelegateAction: Equatable, Sendable {
        /// The user confirmed leaving the stream with the given exit.
        case stopRequested(StreamExitAction)
        /// The user asked to return to the console home screen.
        case goHomeRequested

        /// The changed launch settings were saved; the stream should start again with them.
        case restartRequested
    }

    /// Which ways of leaving the stream the leave confirmation offers.
    public typealias ExitChoices = StreamMenuExitChoices

    /// Where loading and saving the menu settings is, each operation tagged with the id that started it.
    public typealias Phase = StreamMenuPhase

    /// Where controller navigation is in the stream menu, carrying the panel the menu shows or reopens on.
    public typealias Navigation = StreamMenuNavigation

    /// The stream menu's settings, navigation, leave confirmation and diagnostics.
    @ObservableState public struct State: Equatable {
        /// The kind of stream being tuned, which decides where settings load from and save to.
        public var context: StreamTuningContext
        /// Where loading and saving the settings is.
        public var phase = Phase.idle
        /// Where controller navigation is in the menu.
        public var navigation = Navigation.gameplay(.picture)
        /// The tuning last loaded or saved, which the draft is compared against before saving.
        public var configuration = StreamTuningConfiguration()
        /// The tuning the menu's controls edit and push to the live stream.
        public var draft = StreamTuningConfiguration()
        /// Whether the settings have loaded at least once.
        public var hasLoaded = false
        /// The cloud datacenter the stream uses, set by the hosting stream when known.
        public var datacenter: CloudDatacenterSelection?
        /// The cloud bandwidth measurement, set by the hosting stream when known.
        public var bandwidth: CloudBandwidthReport?
        /// The trace label of the control that asked to leave while the leave confirmation shows, else `nil`.
        public var exitRequest: String?
        /// The saved choice for what leaving a console stream does to the console.
        public var leaveAction = ConsoleLeaveAction.ask
        /// The id of the in-flight ``StreamMenuReducer/State/leaveAction`` load, to drop stale results.
        public var leaveLoad: UUID?
        /// The state of the diagnostics overlay.
        public var diagnostics = StreamDiagnosticsReducer.State()
        /// The connection tips topic the Statistics panel shows.
        public var troubleshootTopic = StreamTroubleshootTopic.wifi
        /// The live stream session that draft edits are pushed to, or `nil` before the session starts.
        public var session: StreamSessionID?
        /// Whether the Session panel offers PS Now's Application Saved Data Management, which applies to a PS4
        /// game.
        public var offersSavedData = false
        /// Whether the console currently forbids showing its video, as during protected content.
        public var displayProhibited = false
        /// Whether the console has turned the video stream off.
        public var videoDisabled = false

        /// Creates the menu state for a stream before anything has loaded.
        /// - Parameters:
        ///   - context: The kind of stream being tuned.
        ///   - datacenter: The cloud datacenter, when already known.
        ///   - bandwidth: The cloud bandwidth measurement, when already known.
        public init(
            context: StreamTuningContext,
            datacenter: CloudDatacenterSelection? = nil,
            bandwidth: CloudBandwidthReport? = nil
        ) {
            self.context = context
            self.datacenter = datacenter
            self.bandwidth = bandwidth
        }

        /// Whether the settings have loaded, which edits and saves require.
        public var loaded: Bool {
            hasLoaded
        }

        /// Why 3D audio is unavailable for this stream, or `nil` when the stream carries it.
        public var audio3DDisabledReason: LocalizedStringResource? {
            guard let target = context.soundTarget else {
                return .playbackMenuSpatialAudioGuestUnsupported
            }
            guard draft.audio3DAvailable else {
                return .playbackMenuSpatialAudioTargetUnsupported(target: String(localized: target.title))
            }
            return nil
        }

        /// Whether the stream is from a console, so going home and rest mode are possible.
        public var consoleCommandsAvailable: Bool {
            if case .console = context {
                return true
            }
            return false
        }

        /// The ways to leave that the confirmation offers, from the stream kind and the saved leave action.
        public var exitChoices: ExitChoices {
            guard consoleCommandsAvailable else {
                return .disconnect
            }
            switch leaveAction {
            case .ask:
                return .disconnectOrRestMode
            case .restMode:
                return .restMode
            case .leaveOn:
                return .disconnect
            }
        }
    }

    /// Everything the stream menu responds to.
    public enum Action: Equatable, Sendable {
        /// Starts loading the settings and the console leave action when idle or after a failure.
        case load
        /// The load with the given id finished with this configuration.
        case loaded(UUID, StreamTuningConfiguration)
        /// The load of the console leave action with the given id finished.
        case leaveActionLoaded(UUID, ConsoleLeaveAction)
        /// Replaces the draft and pushes it to the live stream session.
        case edit(StreamTuningConfiguration)
        /// Saves the draft when it differs from the stored configuration.
        case save
        /// The save with the given id stored this configuration.
        case saved(UUID, StreamTuningConfiguration)
        /// The load or save with the given id failed.
        case failed(UUID)
        /// Shows the leave confirmation, recording the trace label of the control that asked.
        case requestExit(String)
        /// Dismisses the leave confirmation.
        case cancelExit
        /// Leaves the stream with the chosen exit, limited to the allowed choices, and saves the draft.
        case confirmExit(StreamExitAction)
        /// Asks the hosting stream to return to the console home screen.
        case goHome
        /// Opens the cloud PS4's Application Saved Data Management screen in a PS Now stream.
        case openSavedData
        /// Saves the changed launch settings and asks the hosting stream to start again with them.
        case restartStream
        /// Opens the control panel from gameplay on the panel it last showed.
        case open
        /// Hands input back to the game, saving the panel's changes when asked.
        case returnToGameplay(save: Bool)
        /// Shows another panel at the current level.
        case selectPanel(StreamMenuPanel)
        /// Shows another topic in the Statistics panel's connection tips.
        case selectTroubleshootTopic(StreamTroubleshootTopic)
        /// Moves the HDR heatmap's brightness marker by controller, from the panel while the heatmap shows.
        case enterMeasuring
        /// Stops moving the brightness marker and returns to the panel.
        case finishMeasuring
        /// Moves the brightness marker one step while measuring.
        case nudgeMarker(BrightnessMarker.Nudge)
        /// The menu left the screen; saves while navigation was active.
        case disappeared
        /// A request for the hosting stream.
        case delegate(DelegateAction)
        /// An action for the diagnostics overlay.
        case diagnostics(StreamDiagnosticsReducer.Action)
    }

    /// Moves the brightness marker and tells PS5 cloud whether the menu covers the stream.
    @Dependency(\.streamSession) var playerControls
    /// Paces the marker's glide.
    @Dependency(\.continuousClock) var clock

    /// How often the left stick glides the brightness marker.
    static let glideInterval = Duration.milliseconds(16)

    /// The effects the menu cancels.
    enum CancelID: Hashable {
        /// The brightness marker's glide while measuring.
        case glide
    }

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.diagnostics, action: \.diagnostics) {
            StreamDiagnosticsReducer()
        }
        CombineReducers {
            StreamMenuSettings()
            Reduce { state, action in
                switch action {
                case .delegate, .diagnostics, .load, .leaveActionLoaded, .loaded, .edit, .save,
                     .restartStream,
                     .saved,
                     .failed:
                    return .none
                case .open:
                    state.navigation.open()
                    return .none
                case .returnToGameplay(let saveChanges):
                    guard state.navigation.isActive else {
                        return .none
                    }
                    let editing = state.navigation.level == .panel || state.navigation.level == .measuring
                    let saving = saveChanges && editing
                        ? StreamMenuSettings().save(&state)
                        : .none
                    state.navigation = .gameplay(state.navigation.panel)
                    return saving
                case .selectPanel(let panel):
                    state.navigation = state.navigation.selecting(panel)
                    return .none
                case .selectTroubleshootTopic(let topic):
                    state.troubleshootTopic = topic
                    return .none
                case .enterMeasuring:
                    guard case .panel(let panel) = state.navigation,
                          state.diagnostics.analysis == .hdrHeatmap else {
                        return .none
                    }
                    state.navigation = .measuring(panel)
                    return .none
                case .finishMeasuring:
                    state.navigation.finishMeasuring()
                    return .none
                case .nudgeMarker(let nudge):
                    guard state.navigation.level == .measuring else {
                        return .none
                    }
                    return .run { [playerControls] _ in
                        await playerControls.nudgeMarker(nudge)
                    }
                case .disappeared:
                    let leaving = Effect<Action>.merge(
                        .cancel(id: CancelID.glide),
                        .run { [playerControls] _ in
                            await playerControls.showMarker(false)
                            await playerControls.coverStreamWithMenu(false)
                        }
                    )
                    guard state.navigation.isActive else {
                        return leaving
                    }
                    return .merge(leaving, StreamMenuSettings().save(&state))
                case .goHome:
                    guard state.consoleCommandsAvailable else {
                        return .none
                    }
                    return .send(.delegate(.goHomeRequested))
                case .openSavedData:
                    guard state.offersSavedData else {
                        return .none
                    }
                    return .run { [playerControls] _ in
                        _ = await playerControls.openSavedData()
                    }
                case .requestExit(let source):
                    if state.exitRequest == nil {
                        state.exitRequest = source
                    }
                    return .none
                case .cancelExit:
                    state.exitRequest = nil
                    return .none
                case .confirmExit(let requested):
                    guard state.exitRequest != nil else {
                        return .none
                    }
                    let exit = state.exitChoices.allowing(requested)
                    state.exitRequest = nil
                    return .merge(.send(.delegate(.stopRequested(exit))), StreamMenuSettings().save(&state))
                }
            }
        }
        .onChange(of: \.navigation.level) { previous, level in
            Reduce { _, _ in
                measuringChanged(from: previous, to: level)
            }
        }
        .onChange(of: \.navigation.isActive) { _, active in
            Reduce { _, _ in
                .run { [playerControls] _ in
                    await playerControls.coverStreamWithMenu(active)
                }
            }
        }
    }

    private static func glide(
        on clock: some Clock<Duration>,
        controls: StreamSessionClient
    ) async throws {
        var last = clock.now
        while !Task.isCancelled {
            try await clock.sleep(for: glideInterval)
            let now = clock.now
            let elapsed = last.duration(to: now)
            last = now
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            await controls.glideMarker(seconds)
        }
    }

    private func measuringChanged(
        from previous: Navigation.Level,
        to level: Navigation.Level
    ) -> Effect<Action> {
        if level == .measuring {
            return .run { [playerControls, clock] _ in
                await playerControls.placeMarker(.centre)
                await playerControls.showMarker(true)
                try await Self.glide(on: clock, controls: playerControls)
            }
            .cancellable(id: CancelID.glide, cancelInFlight: true)
        }
        guard previous == .measuring else {
            return .none
        }
        return .merge(
            .cancel(id: CancelID.glide),
            .run { [playerControls] _ in
                await playerControls.showMarker(false)
            }
        )
    }
}

/// Which ways of leaving the stream the leave confirmation offers.
public enum StreamMenuExitChoices: Equatable, Sendable {
    /// Only disconnecting, leaving the console on.
    case disconnect
    /// A choice between disconnecting and putting the console in rest mode.
    case disconnectOrRestMode
    /// Only putting the console in rest mode.
    case restMode

    /// Limits a requested exit to the ones offered.
    ///
    /// - Parameter exit: The exit the person chose.
    /// - Returns: The exit, or the only one offered.
    public func allowing(_ exit: StreamExitAction) -> StreamExitAction {
        switch self {
        case .disconnect:
            .disconnect
        case .restMode:
            .restMode
        case .disconnectOrRestMode:
            exit
        }
    }
}

/// Where controller navigation is in the stream menu, carrying the panel the menu shows or reopens on.
///
/// ```
/// gameplay --open--> panel
/// panel --enterMeasuring (heatmap on)--> measuring --finishMeasuring--> panel
/// panel, measuring --returnToGameplay--> gameplay
/// gameplay, panel, measuring --selectPanel--> the same level on that panel, measuring as panel
/// ```
public enum StreamMenuNavigation: Equatable, Sendable {
    /// Which level navigation is at, without the panel.
    public enum Level: Equatable, Sendable {
        /// Input plays the game.
        case gameplay
        /// The control panel is open.
        case panel
        /// The brightness marker on the HDR heatmap is moved by controller.
        case measuring
    }

    /// Input plays the game; the panel is the one the menu reopens on.
    case gameplay(StreamMenuPanel)
    /// The control panel shows the panel.
    case panel(StreamMenuPanel)
    /// The brightness marker is moved; the panel is the one measuring returns to.
    case measuring(StreamMenuPanel)

    /// The level, without the panel.
    public var level: Level {
        switch self {
        case .gameplay:
            .gameplay
        case .panel:
            .panel
        case .measuring:
            .measuring
        }
    }

    /// The panel the menu shows, or shows once entered.
    public var panel: StreamMenuPanel {
        switch self {
        case .gameplay(let panel), .panel(let panel), .measuring(let panel):
            panel
        }
    }

    /// Whether the menu holds controller navigation.
    public var isActive: Bool {
        level != .gameplay
    }

    /// Shows another panel at the same level; choosing a panel while measuring returns to the panel.
    ///
    /// - Parameter panel: The panel to show.
    /// - Returns: The navigation showing that panel.
    func selecting(_ panel: StreamMenuPanel) -> StreamMenuNavigation {
        switch self {
        case .gameplay:
            .gameplay(panel)
        case .panel, .measuring:
            .panel(panel)
        }
    }

    /// Opens the control panel on the panel it last showed, when input plays the game.
    public mutating func open() {
        if case .gameplay(let panel) = self {
            self = .panel(panel)
        }
    }

    /// Returns from moving the brightness marker to the panel.
    public mutating func finishMeasuring() {
        if case .measuring(let panel) = self {
            self = .panel(panel)
        }
    }
}

/// Where loading and saving the menu settings is, each operation tagged with the id that started it.
public enum StreamMenuPhase: Equatable {
    /// Nothing has been loaded yet.
    case idle
    /// The settings are loading under the given operation id.
    case loading(UUID)
    /// The settings are loaded and nothing is being saved.
    case ready
    /// The draft is being saved under the given operation id.
    case saving(UUID)
    /// The draft is being saved under the given operation id, after which the stream starts again.
    case savingToRelaunch(UUID)
    /// The last load or save failed.
    case failed
}

/// Loads, live-tunes and saves the stream menu's picture and sound settings, and loads the console leave
/// action.
///
/// Every load and save is tagged with the id that started it, so only the latest one moves the
/// ``StreamMenuPhase``. A draft edit is pushed to the live stream session, replacing a push still in flight.
private struct StreamMenuSettings: Reducer {
    /// The stream menu's state.
    typealias State = StreamMenuReducer.State

    /// What the stream menu responds to.
    typealias Action = StreamMenuReducer.Action

    private enum TuneID {
        case push
    }

    @Dependency(\.settings) private var power
    @Dependency(\.logger) private var logger
    @Dependency(\.uuid) private var uuid
    @Dependency(\.streamSession) private var streamSession

    /// Reacts to loading, editing and saving the settings.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                return load(&state)
            case let .leaveActionLoaded(id, value):
                guard state.leaveLoad == id else {
                    return .none
                }
                state.leaveLoad = nil
                state.leaveAction = value
                return .none
            case let .loaded(id, value):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.configuration = value
                state.draft = value
                state.hasLoaded = true
                state.phase = .ready
                return .none
            case let .edit(value):
                return edit(&state, to: value)
            case .save:
                return save(&state)
            case .restartStream:
                return saveToRelaunch(&state)
            case let .saved(id, value):
                return saved(&state, id: id, value: value)
            case let .failed(id):
                guard state.phase == .loading(id) || state.phase == .saving(id)
                    || state.phase == .savingToRelaunch(id) else {
                    return .none
                }
                state.phase = .failed
                return .none
            default:
                return .none
            }
        }
    }

    /// Saves the draft when it differs from the stored configuration.
    ///
    /// - Parameter state: The stream menu's state.
    /// - Returns: The effect that saves the draft, or none.
    func save(_ state: inout State) -> Effect<Action> {
        guard state.loaded, state.draft != state.configuration else {
            return .none
        }
        let id = uuid()
        state.phase = .saving(id)
        return persist(state.draft, context: state.context, id: id)
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard state.phase == .idle || state.phase == .failed else {
            return .none
        }
        let id = uuid()
        let context = state.context
        state.phase = .loading(id)
        return .merge(
            .run { [streamSession] send in
                do {
                    await send(.loaded(id, try await streamSession.loadTuning(context)))
                } catch {
                    await send(.failed(id))
                }
            },
            loadLeaveAction(&state)
        )
    }

    private func edit(_ state: inout State, to value: StreamTuningConfiguration) -> Effect<Action> {
        guard state.loaded, value != state.draft else {
            return .none
        }
        state.draft = value
        guard let session = state.session else {
            return .none
        }
        return .run { [streamSession] _ in
            await streamSession.tune(session, value)
        }
        .cancellable(id: TuneID.push, cancelInFlight: true)
    }

    private func saved(_ state: inout State, id: UUID, value: StreamTuningConfiguration) -> Effect<Action> {
        switch state.phase {
        case .saving(id):
            state.configuration = value
            state.phase = .ready
            return .none
        case .savingToRelaunch(id):
            state.configuration = value
            state.phase = .ready
            return .send(.delegate(.restartRequested))
        default:
            return .none
        }
    }

    private func loadLeaveAction(_ state: inout State) -> Effect<Action> {
        guard state.consoleCommandsAvailable else {
            return .none
        }
        let id = uuid()
        state.leaveLoad = id
        return .run { [power, logger] send in
            do {
                await send(.leaveActionLoaded(
                    id,
                    try await power.load(ConsolePowerSettings.self).leaveAction
                ))
            } catch {
                await logger.log(.diagnostic(
                    .playback, .warning,
                    "Saved console power settings could not be loaded (\(LogFormat.error(error))); leaving a stream "
                        + "asks whether to put the console in rest mode"
                ))
                await send(.leaveActionLoaded(id, .ask))
            }
        }
    }

    private func saveToRelaunch(_ state: inout State) -> Effect<Action> {
        guard state.loaded, state.draft.restartNeeded else {
            return .none
        }
        guard state.draft != state.configuration else {
            return .send(.delegate(.restartRequested))
        }
        let id = uuid()
        state.phase = .savingToRelaunch(id)
        return persist(state.draft, context: state.context, id: id)
    }

    private func persist(_ value: StreamTuningConfiguration, context: StreamTuningContext,
                         id: UUID) -> Effect<Action> {
        .run { [streamSession, logger] send in
            do {
                try await streamSession.saveTuning(context, value)
                await send(.saved(id, value))
            } catch {
                await logger.log(.diagnostic(
                    .playback, .warning,
                    "The stream menu settings could not be saved (\(LogFormat.error(error)))"
                ))
                await send(.failed(id))
            }
        }
    }
}
