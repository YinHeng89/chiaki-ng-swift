import ChiakiModels
import Foundation

/// Every repository over one open ``AppDatabase``, built once and shared.
///
/// The app opens this at its user data location; the core's store adapters and the app's features reach
/// persistence only through the repositories it holds.
public final class AppRepositories: Sendable {
    /// The open database.
    public let database: AppDatabase

    /// The account list.
    public let accounts: AccountRepository

    /// The core's signed-in accounts and home users.
    public let credentials: CredentialRepository

    /// Saved consoles and pairings.
    public let consoles: ConsoleRepository

    /// What consoles do at launch and their login PINs.
    public let consoleLaunch: ConsoleLaunchRepository

    /// Typed settings.
    public let settings: SettingsRepository

    /// The controls configuration.
    public let controls: ControlsRepository

    /// Per-account cached resources.
    public let resources: AccountResourceRepository

    /// The installation's cloud device id.
    public let installation: CloudInstallationRepository

    /// Cloud datacenter measurements.
    public let datacenters: DatacenterMeasurementRepository

    /// The Kakusan identity and remembered devices.
    public let devices: KakusanDeviceRepository

    /// The PS5 cloud captures waiting to be saved.
    public let captures: CloudCaptureRepository

    /// Builds every repository over an open database.
    ///
    /// - Parameters:
    ///   - database: The open, migrated database.
    ///   - report: Receives the storage failures the core's stores turn into plain failures, so they can be
    ///     logged.
    public init(database: AppDatabase, report: @escaping @Sendable (PersistenceError) -> Void = { _ in }) {
        self.database = database
        accounts = AccountRepository(database: database)
        credentials = CredentialRepository(database: database, report: report)
        consoles = ConsoleRepository(database: database, report: report)
        consoleLaunch = ConsoleLaunchRepository(database: database)
        settings = SettingsRepository(database: database)
        controls = ControlsRepository(database: database)
        resources = AccountResourceRepository(database: database)
        installation = CloudInstallationRepository(database: database)
        datacenters = DatacenterMeasurementRepository(database: database, report: report)
        devices = KakusanDeviceRepository(database: database, report: report)
        captures = CloudCaptureRepository(database: database)
    }

    /// Opens the database at a user data location and builds every repository over it.
    ///
    /// - Parameters:
    ///   - data: The location.
    ///   - report: Receives storage failures of the core's stores.
    /// - Returns: The repositories, with the installation's cloud device id created.
    /// - Throws: The errors of ``AppDatabase/open(_:)`` and ``CloudInstallationRepository/deviceID()``.
    public static func open(
        _ data: UserData,
        report: @escaping @Sendable (PersistenceError) -> Void = { _ in }
    ) throws(PersistenceError) -> AppRepositories {
        let repositories = try AppRepositories(database: AppDatabase.open(data), report: report)
        _ = try repositories.installation.deviceID()
        return repositories
    }
}
