import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus

/// The settings panel: which tab is shown, every pane's state and what it presents.
///
/// Every pane's state lives here for as long as the app runs, so switching tabs, closing the panel or
/// resizing the window never loses an edit; only the selected tab's view is mounted, so only it runs appear
/// effects. Whether the panel is open is ``RootFeature``'s `settings` destination. The error report and the
/// clear-cache confirmation are presented through `destination`.
@Reducer
public struct SettingsFeature {
    /// What the panel presents over itself.
    @Reducer
    public enum Destination {
        /// The built error report.
        case errorReport(ErrorReportFeature)

        /// The question before a cache is cleared.
        case clearCache(ClearCacheConfirmation)
    }

    /// The panel's state.
    @ObservableState
    public struct State: Equatable {
        /// The tab that is shown.
        public internal(set) var route = SettingsRoute.about

        /// What the panel presents.
        @Presents public var destination: Destination.State?

        /// Console picture settings.
        public var picture = PersistedSettingFeature<PictureSettings>.State()

        /// Cloud picture settings.
        public var cloudPicture = CloudPictureSettingsFeature.State()

        /// Sound settings and devices.
        public var sound = SoundSettingsFeature.State()

        /// Controls.
        public var controls = ControlsSettingsFeature.State()

        /// Interface settings.
        public var interface = PersistedSettingFeature<InterfaceSettings>.State()

        /// Discovery settings.
        public var network = NetworkSettingsFeature.State()

        /// Whether a datacenter is chosen at launch.
        public var cloudLaunch = CloudLaunchSettingsReducer.State()

        /// Console power settings.
        public var consolePower = PersistedSettingFeature<ConsolePowerSettings>.State()

        /// Internet connection settings.
        public var internetConnection = PersistedSettingFeature<InternetConnectionSettings>.State()

        /// The NAT type check.
        public var natType = NatTypeFeature.State()

        /// PlayStation accessibility settings sent with cloud stream launches.
        public var playStationAccessibility = PersistedSettingFeature<PlayStationAccessibilitySettings>
            .State()

        /// Logging settings, including streamer mode.
        public var logging = PersistedSettingFeature<LogSettings>.State()

        /// Takion versions, log health and the error report.
        public var developer = DeveloperSettingsFeature.State()

        /// Entitlement explanations.
        public var entitlements = EntitlementsReducer.State()

        /// Caches.
        public var caches = CachesReducer.State()

        /// Recorded requests.
        public var requests = RequestsReducer.State()

        /// Held tokens.
        public var tokens = TokensReducer.State()

        /// The About tab.
        public var about = AboutReducer.State()

        /// Kakusan settings.
        public var kakusan = KakusanSettingsFeature.State()

        /// Whether any saved account is signed in to PlayStation Network, which hides the PSN-only tabs and
        /// sections while none is.
        public internal(set) var psnReach = PSNReach.localOnly

        /// Creates the panel on the About tab.
        public init() {}

        /// The logging settings in force: the saved value once loaded, else the defaults.
        public var logSettings: LogSettings {
            logging.saved ?? logging.draft
        }

        /// The tabs the panel shows, in order.
        public var tabs: [SettingsRoute] {
            SettingsRoute.shown(for: psnReach)
        }
    }

    /// Everything the settings panel reacts to.
    public enum Action: Equatable, Sendable {
        /// The app launched: loads the settings the app reads outside the panel.
        case launched

        /// The panel closed: what it presented is dismissed.
        case closed

        /// Shows a tab.
        case select(SettingsRoute)

        /// The saved accounts' PlayStation Network reach changed; a parent sends it.
        case psnReach(PSNReach)

        /// What the panel presents.
        case destination(PresentationAction<Destination.Action>)

        /// Console picture settings.
        case picture(PersistedSettingFeature<PictureSettings>.Action)

        /// Cloud picture settings.
        case cloudPicture(CloudPictureSettingsFeature.Action)

        /// Sound settings.
        case sound(SoundSettingsFeature.Action)

        /// Controls.
        case controls(ControlsSettingsFeature.Action)

        /// Interface settings.
        case interface(PersistedSettingFeature<InterfaceSettings>.Action)

        /// Discovery settings.
        case network(NetworkSettingsFeature.Action)

        /// Datacenter choice at launch.
        case cloudLaunch(CloudLaunchSettingsReducer.Action)

        /// Console power settings.
        case consolePower(PersistedSettingFeature<ConsolePowerSettings>.Action)

        /// Internet connection settings.
        case internetConnection(PersistedSettingFeature<InternetConnectionSettings>.Action)

        /// The NAT type check.
        case natType(NatTypeFeature.Action)

        /// PlayStation accessibility settings.
        case playStationAccessibility(PersistedSettingFeature<PlayStationAccessibilitySettings>.Action)

        /// Logging settings.
        case logging(PersistedSettingFeature<LogSettings>.Action)

        /// The Developer tab.
        case developer(DeveloperSettingsFeature.Action)

        /// Entitlements.
        case entitlements(EntitlementsReducer.Action)

        /// Caches.
        case caches(CachesReducer.Action)

        /// Requests.
        case requests(RequestsReducer.Action)

        /// Tokens.
        case tokens(TokensReducer.Action)

        /// The About tab.
        case about(AboutReducer.Action)

        /// Kakusan settings.
        case kakusan(KakusanSettingsFeature.Action)
    }

    @Dependency(\.continuousClock) private var clock
    @Dependency(\.streamSession) private var streamPlayerControls

    private enum CancelID {
        case accessibilityUpdate
    }

    /// How long saved PlayStation accessibility settings must stay unchanged before a playing stream is sent
    /// them, so dragging a slider sends one update.
    public static let accessibilitySettle = Duration.milliseconds(600)

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.picture, action: \.picture) {
            PersistedSettingFeature<PictureSettings>()
        }
        Scope(state: \.cloudPicture, action: \.cloudPicture) {
            CloudPictureSettingsFeature()
        }
        Scope(state: \.sound, action: \.sound) {
            SoundSettingsFeature()
        }
        Scope(state: \.controls, action: \.controls) {
            ControlsSettingsFeature()
        }
        Scope(state: \.interface, action: \.interface) {
            PersistedSettingFeature<InterfaceSettings>()
        }
        Scope(state: \.network, action: \.network) {
            NetworkSettingsFeature()
        }
        Scope(state: \.cloudLaunch, action: \.cloudLaunch) {
            CloudLaunchSettingsReducer()
        }
        Scope(state: \.consolePower, action: \.consolePower) {
            PersistedSettingFeature<ConsolePowerSettings>()
        }
        Scope(state: \.internetConnection, action: \.internetConnection) {
            PersistedSettingFeature<InternetConnectionSettings>()
        }
        Scope(state: \.natType, action: \.natType) {
            NatTypeFeature()
        }
        Scope(state: \.playStationAccessibility, action: \.playStationAccessibility) {
            PersistedSettingFeature<PlayStationAccessibilitySettings>()
        }
        Scope(state: \.logging, action: \.logging) {
            PersistedSettingFeature<LogSettings>()
        }
        Scope(state: \.developer, action: \.developer) {
            DeveloperSettingsFeature()
        }
        Scope(state: \.entitlements, action: \.entitlements) {
            EntitlementsReducer()
        }
        Scope(state: \.caches, action: \.caches) {
            CachesReducer()
        }
        Scope(state: \.requests, action: \.requests) {
            RequestsReducer()
        }
        Scope(state: \.tokens, action: \.tokens) {
            TokensReducer()
        }
        Scope(state: \.about, action: \.about) {
            AboutReducer()
        }
        Scope(state: \.kakusan, action: \.kakusan) {
            KakusanSettingsFeature()
        }
        Reduce { state, action in
            switch action {
            case .launched:
                return .merge(
                    .send(.logging(.appeared)),
                    .send(.interface(.appeared)),
                    .send(.controls(.appeared))
                )
            case .closed:
                state.destination = nil
                return .none
            case let .select(route):
                state.route = route
                return .none
            case let .psnReach(reach):
                state.psnReach = reach
                guard !state.tabs.contains(state.route) else {
                    return .none
                }
                return .send(.select(.picture))
            case let .playStationAccessibility(.delegate(.committed(settings))):
                return .run { [clock, streamPlayerControls] _ in
                    try await clock.sleep(for: Self.accessibilitySettle)
                    await streamPlayerControls.updateAccessibility(settings)
                }
                .cancellable(id: CancelID.accessibilityUpdate, cancelInFlight: true)
            case let .developer(.delegate(.reportReady(text))):
                state.destination = .errorReport(ErrorReportFeature.State(text: text))
                return .none
            case let .caches(.delegate(.confirmClear(clearing))):
                state.destination = .clearCache(ClearCacheConfirmation.State(clearing))
                return .none
            case .destination(.presented(.clearCache(.confirm))):
                guard case let .clearCache(confirmation) = state.destination else {
                    return .none
                }
                state.destination = nil
                return .send(.caches(.clear(confirmation.clearing)))
            case .destination, .picture, .cloudPicture, .sound, .controls, .interface, .network, .cloudLaunch,
                 .consolePower, .internetConnection, .natType, .playStationAccessibility, .logging,
                 .developer,
                 .entitlements,
                 .caches, .requests, .tokens, .about, .kakusan:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension SettingsFeature.Destination.State: Equatable {}

extension SettingsFeature.Destination.Action: Equatable, Sendable {}

extension SettingsFeature.State {
    /// The prompt that asks before clearing a cache, while it is shown.
    var clearCacheConfirmation: AppConfirmation? {
        guard case let .clearCache(confirmation) = destination else {
            return nil
        }
        return confirmation.confirmation
    }
}
