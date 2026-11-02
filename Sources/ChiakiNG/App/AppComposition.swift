import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import ChiakiPersistence
import PlatformUI
import Dependencies

/// The app's composition root: every live dependency, built once over one user data location.
///
/// The entry point builds one composition for the launch's `UserData` and calls ``prepare()``
/// before anything reads a dependency. From then on the root store, the command-line commands and the
/// diagnostics all reach the same `AccountService`, which owns the one database connection, and the same
/// logging pipeline, which persists its settings through that connection.
@MainActor
final class AppComposition {
    /// Where the database, the catalog, the logs and the caches live.
    let userData: UserData

    /// The one owner of the app database and the core.
    let accounts: AccountService

    /// The one logging pipeline.
    let logging: LogPipeline

    /// The one native stream lease, which keeps the display awake while a stream runs.
    let streamLeases: StreamLeases

    /// The one set of controller services and the menu navigator over them.
    let input: InputServices

    /// Tells console catalog readers that the pairings changed.
    let consoleCatalogChanges = ConsoleCatalogChanges()

    /// What the stream menu and the diagnostics ask of the live player, kept across players.
    let playerControls: StreamPlayerControls

    /// Saves PS5 cloud captures to this device, finishing interrupted saves on the next launch.
    let cloudCaptures: CloudCaptureSaver

    /// The one reader of the PS5 cloud library, shared by the catalog and the entitlements.
    let cloudLibrary = CloudLibraryService.overCore()

    /// The one control over the app window's launch presentation.
    let window = LaunchWindowControl()

    /// The downsampled art copies every scaled art view shares.
    let scaledArt = ScaledArtCache()

    /// The measured art content bounds every art view shares.
    let artBounds = ArtContentBounds()

    /// The sample art every developer preview card shares.
    let sampleArt = SampleArtStudio()

    /// Builds every live dependency over a user data location.
    ///
    /// Nothing is opened yet; the database opens on first use.
    ///
    /// - Parameters:
    ///   - userData: The launch's location.
    ///   - database: Opens and migrates the app database.
    init(userData: UserData, database: AppDatabaseClient) {
        self.userData = userData
        let accounts = AccountService(data: userData, database: database)
        self.accounts = accounts
        logging = LogPipeline(
            store: Self.logSettings(in: accounts), appVersion: AppVersion.display(), system: .live
        )
        let streamLeases = StreamLeases {
            DisplayAwakeAssertion.hold()
        }
        self.streamLeases = streamLeases
        let input = InputServices(leases: streamLeases) { action in
            _ = ChiakiNGApp.store.send(.virtualGamepad(action))
        }
        self.input = input
        playerControls = StreamPlayerControls(input: input.coordinator)
        cloudCaptures = CloudCaptureSaver(accounts: accounts)
    }

    /// Builds the live composition for a user data location, with the real database.
    ///
    /// - Parameter userData: The launch's location.
    /// - Returns: The composition.
    static func live(_ userData: UserData) -> AppComposition {
        AppComposition(userData: userData, database: .liveValue)
    }

    /// Makes this composition's values the process's dependencies.
    ///
    /// Call once, before any dependency is read.
    func prepare() {
        prepareDependencies {
            install(into: &$0)
        }
        input.coordinator.streamControls = playerControls
    }

    /// Writes every live dependency into a set of values.
    ///
    /// - Parameter values: The values to fill.
    func install(into values: inout DependencyValues) {
        values.accountService = accounts
        values.logger = logging.logger
        values.logSettings = logging.settingsClient
        values.liveLog = logging.liveLogClient
        values.accounts = .native(accounts, coordinator: input.coordinator)
        values.consoles = .live(accounts, changes: consoleCatalogChanges)
        values.streamLeases = streamLeases
        values.platform = PlatformClient.live(
            leases: streamLeases,
            allowSleep: { notification in
                await ChiakiApplicationDelegate.power.allowSleep(notification)
            }
        ).presenting(through: window)
        values.catalog = .live(library: cloudLibrary)
        values.streamSession = StreamSessionClient.live(
            leases: streamLeases,
            launcher: NativeStreamLauncher(controls: playerControls, captures: cloudCaptures, inputs: input)
        )
        .controlling(playerControls)
        .seating(input.coordinator)
        .capturingMicrophone(light: input.microphoneLight)
        .reachingPSN(through: accounts, captures: cloudCaptures)
        values.psnMessages = .live(accounts)
        values.psnTrophies = .live(accounts)
        values.network = .live
        values.controllers = .native(input.backend, lights: input.lights)
        values.virtualGamepadLink = input.virtualGamepadLink
        values.openURL = OpenURLEffect { url in
            await PlatformWorkspace.open(url)
        }
    }

    private static func logSettings(in accounts: AccountService) -> LogSettingsStore {
        LogSettingsStore(
            load: {
                try await accounts.storage().settings.value(SettingKeys.logging)
            },
            save: { settings in
                try await accounts.storage().settings.save(settings, for: SettingKeys.logging)
            }
        )
    }
}
