import ChiakiModels
import Dependencies
import Foundation

/// Reaches PS Cloud: reads and refreshes each account's stored cloud status, and loads, saves and announces the
/// player's cloud datacenter choice.
public struct CloudClient: Sendable {
    /// Returns the stored status snapshot for a scope, or `nil` when none is usable.
    public var cachedStatus: @Sendable (CloudAccountScope) async throws -> CloudStatusSnapshot?
    /// Fetches, stores and returns a fresh status snapshot for a scope.
    public var refreshStatus: @Sendable (CloudAccountScope) async throws -> CloudStatusSnapshot
    /// Reads the saved datacenter setting from the database.
    public var loadDatacenters: @Sendable () async throws -> CloudDatacenterSettings
    /// Saves a datacenter setting and announces it to every listener.
    public var saveDatacenters: @Sendable (CloudDatacenterSettings) async throws -> Void
    /// Opens a stream of every datacenter setting saved from now on.
    public var datacenterChanges: @Sendable () async -> AsyncStream<CloudDatacenterSettings>
    /// Turns choosing a datacenter at each launch on or off, then saves and announces the result.
    public var setSelectAtLaunch: @Sendable (Bool) async throws -> CloudDatacenterSettings
    /// Records a connection to a datacenter with its round trip time and service, then saves and announces
    /// the result.
    public var recordConnection: @Sendable (
        String, Int, CloudDatacenterService
    ) async throws -> CloudDatacenterSettings

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - cachedStatus: Returns the stored status snapshot, if usable.
    ///   - refreshStatus: Fetches, stores and returns a fresh status snapshot.
    ///   - loadDatacenters: Reads the saved datacenter setting from the database.
    ///   - saveDatacenters: Saves a datacenter setting and announces it to every listener.
    ///   - datacenterChanges: Opens a stream of every datacenter setting saved from now on.
    ///   - setSelectAtLaunch: Turns choosing a datacenter at each launch on or off, then saves and announces the
    ///     result.
    ///   - recordConnection: Records a connection to a datacenter with its round trip time and service, then saves
    ///     and announces the result.
    public init(
        cachedStatus: @escaping @Sendable (CloudAccountScope) async throws -> CloudStatusSnapshot?,
        refreshStatus: @escaping @Sendable (CloudAccountScope) async throws -> CloudStatusSnapshot,
        loadDatacenters: @escaping @Sendable () async throws -> CloudDatacenterSettings,
        saveDatacenters: @escaping @Sendable (CloudDatacenterSettings) async throws -> Void,
        datacenterChanges: @escaping @Sendable () async -> AsyncStream<CloudDatacenterSettings>,
        setSelectAtLaunch: @escaping @Sendable (Bool) async throws -> CloudDatacenterSettings,
        recordConnection: @escaping @Sendable (String, Int, CloudDatacenterService) async throws
            -> CloudDatacenterSettings
    ) {
        self.cachedStatus = cachedStatus
        self.refreshStatus = refreshStatus
        self.loadDatacenters = loadDatacenters
        self.saveDatacenters = saveDatacenters
        self.datacenterChanges = datacenterChanges
        self.setSelectAtLaunch = setSelectAtLaunch
        self.recordConnection = recordConnection
    }
}

extension CloudClient: TestDependencyKey {
    /// Has no status cached and cannot refresh it, and keeps a default datacenter setting in memory, saving
    /// nothing and never announcing a change.
    public static let testValue = Self(
        cachedStatus: { _ in
            nil
        },
        refreshStatus: { _ in
            throw CloudStatusFailure.notIntegrated
        },
        loadDatacenters: {
            CloudDatacenterSettings()
        },
        saveDatacenters: { _ in
        },
        datacenterChanges: {
            AsyncStream { $0.finish() }
        },
        setSelectAtLaunch: { enabled in
            CloudDatacenterSettings().selectingAtLaunch(enabled)
        },
        recordConnection: { name, rttMs, service in
            CloudDatacenterSettings().connecting(to: name, rttMs: rttMs, service: service, at: Date())
        }
    )
}

extension DependencyValues {
    /// Reaches PS Cloud: the selected account's cloud status and the player's datacenter choice.
    public var cloud: CloudClient {
        get {
            self[CloudClient.self]
        }
        set {
            self[CloudClient.self] = newValue
        }
    }
}
