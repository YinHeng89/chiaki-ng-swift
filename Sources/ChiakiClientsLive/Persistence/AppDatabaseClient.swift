import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture

/// Opens the app database for the feature that owns the `ChiakiModels/DatabaseOpening` machine.
///
/// The owner begins an attempt with `ChiakiModels/DatabaseOpening/begin(_:)`, calls ``open`` and finishes
/// the same attempt with the result, so a superseded attempt cannot reopen or fail the database.
@DependencyClient
public struct AppDatabaseClient: Sendable {
    /// Opens and migrates the database at a user data location.
    ///
    /// - Parameter data: Where the app keeps its files and how it reaches its keys.
    /// - Returns: The open database, or why it could not be opened.
    public var open: @Sendable (_ data: UserData) async -> Result<AppDatabase, DatabaseOpenFailure> = { _ in
        .failure(.unavailable)
    }
}

extension AppDatabaseClient: DependencyKey {
    /// Opens the database file at the location.
    public static let liveValue = AppDatabaseClient(
        open: { data in
            Result { () throws(PersistenceError) in
                try AppDatabase.open(data)
            }
            .mapError(failure(of:))
        }
    )

    /// Fails the test when a feature opens the database without overriding ``open``.
    public static let testValue = AppDatabaseClient()

    /// The open failure a persistence error stands for.
    ///
    /// - Parameter error: What the database reported.
    /// - Returns: The failure the open machine records.
    static func failure(of error: PersistenceError) -> DatabaseOpenFailure {
        switch error {
        case .unsupportedVersion:
            .unsupportedVersion
        case .invalidMigrations, .corruptData:
            .corrupt
        case .missingKey, .keyUnavailable:
            .keyUnavailable
        case .refusedLiveData:
            .refusedLiveData
        case .database, .invalidInput, .location:
            .unavailable
        }
    }
}

extension DependencyValues {
    /// Opens the app database.
    public var appDatabase: AppDatabaseClient {
        get {
            self[AppDatabaseClient.self]
        }
        set {
            self[AppDatabaseClient.self] = newValue
        }
    }
}
