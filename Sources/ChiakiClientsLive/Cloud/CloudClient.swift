import ChiakiClients
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

extension CloudClient: DependencyKey {
    /// Reads and refreshes the cloud status through the account service's ``CloudStatusService``, and stores the
    /// datacenter setting in the account database, publishing each change through one broadcast.
    ///
    /// Picking a datacenter is a developer tool, so release builds load
    /// `CloudDatacenterSettings.choosingAutomatically()` and ignore any choice a debug
    /// build saved.
    public static let liveValue: CloudClient = {
        let broadcast = CloudDatacenterBroadcast()
        return Self(
            cachedStatus: { scope in
                @Dependency(\.accountService) var accountService
                return try await accountService.cloud().cached(scope)
            },
            refreshStatus: { scope in
                @Dependency(\.accountService) var accountService
                return try await accountService.cloud().refresh(scope)
            },
            loadDatacenters: {
                @Dependency(\.accountService) var accountService
                let settings = try await CloudDatacenterStore(repositories: accountService.storage())
                    .settings()
                #if DEBUG
                    return settings
                #else
                    return settings.choosingAutomatically()
                #endif
            },
            saveDatacenters: { value in
                @Dependency(\.accountService) var accountService
                try await CloudDatacenterStore(repositories: accountService.storage()).save(value)
                await broadcast.publish(value)
            },
            datacenterChanges: {
                await broadcast.stream()
            },
            setSelectAtLaunch: { enabled in
                @Dependency(\.accountService) var accountService
                let value = try await CloudDatacenterStore(repositories: accountService.storage()).update {
                    $0.selectingAtLaunch(enabled)
                }
                await broadcast.publish(value)
                return value
            },
            recordConnection: { name, rttMs, service in
                let now = Date()
                @Dependency(\.accountService) var accountService
                let value = try await CloudDatacenterStore(repositories: accountService.storage()).update {
                    $0.connecting(to: name, rttMs: rttMs, service: service, at: now)
                }
                await broadcast.publish(value)
                return value
            }
        )
    }()
}

/// Fans each saved datacenter setting out to every live listener, so open views follow changes made elsewhere
/// in the app.
private actor CloudDatacenterBroadcast {
    private var continuations = [UUID: AsyncStream<CloudDatacenterSettings>.Continuation]()

    /// Opens a listener that receives every setting published from now on, keeping only the newest one when
    /// it falls behind.
    ///
    /// - Returns: A stream that stays registered until the listener stops iterating it.
    func stream() -> AsyncStream<CloudDatacenterSettings> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CloudDatacenterSettings.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { _ in
            Task {
                await self.remove(id)
            }
        }
        return stream
    }

    /// Sends a saved setting to every open listener.
    ///
    /// - Parameter value: The datacenter setting that was just saved.
    func publish(_ value: CloudDatacenterSettings) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}

/// The app's view of cloud datacenter settings: the user's choices from the settings table joined with the
/// measurements the datacenter repository owns.
///
/// Saving writes only the choices. Measurements are written by the core through its store adapter; the app
/// only ever forgets them all, when it saves settings that hold none.
private struct CloudDatacenterStore {
    /// The repositories the settings are read from and written to.
    let repositories: AppRepositories

    /// The choices joined with every service's measurements.
    ///
    /// - Returns: The settings.
    /// - Throws: `ChiakiPersistence/PersistenceError` or `ChiakiModels/DatacenterStoreFailure`.
    func settings() throws -> CloudDatacenterSettings {
        var settings = try repositories.settings.value(SettingKeys.cloudDatacenters)
        for service in CloudDatacenterService.allCases {
            let measurements = try repositories.datacenters.measurements(for: Self.cloudService(of: service))
            settings.setMeasurements(measurements.map(Self.measurement), for: service)
        }
        return settings
    }

    /// Saves the choices; settings without measurements also forget every stored measurement.
    ///
    /// - Parameter value: The settings.
    /// - Throws: `ChiakiPersistence/PersistenceError` or `ChiakiModels/DatacenterStoreFailure`.
    func save(_ value: CloudDatacenterSettings) throws {
        try repositories.settings.save(Self.choices(of: value), for: SettingKeys.cloudDatacenters)
        if !value.hasMeasurements {
            try repositories.datacenters.forgetAll()
        }
    }

    /// Changes the choices in one transaction and returns the joined settings.
    ///
    /// - Parameter change: Returns new choices from the stored ones.
    /// - Returns: The settings after the change.
    /// - Throws: `ChiakiPersistence/PersistenceError` or `ChiakiModels/DatacenterStoreFailure`.
    func update(_ change: (CloudDatacenterSettings) -> CloudDatacenterSettings) throws
        -> CloudDatacenterSettings {
        try repositories.settings.update(SettingKeys.cloudDatacenters) {
            Self.choices(of: change($0))
        }
        return try settings()
    }

    private static func choices(of value: CloudDatacenterSettings) -> CloudDatacenterSettings {
        var choices = value
        for service in CloudDatacenterService.allCases {
            choices.setMeasurements([], for: service)
        }
        return choices
    }

    private static func cloudService(of service: CloudDatacenterService) -> CloudService {
        switch service {
        case .psNow:
            .psNow
        case .psCloud:
            .psCloud
        }
    }

    private static func measurement(_ stored: DatacenterMeasurement) -> CloudDatacenterMeasurement {
        CloudDatacenterMeasurement(
            name: stored.name,
            rttMs: stored.roundTripMs,
            rttsMs: stored.samplesMs,
            mtuIn: stored.mtuIn,
            mtuOut: stored.mtuOut,
            port: stored.port,
            publicIP: stored.publicAddress,
            maxBandwidth: stored.maxBandwidth,
            measuredAt: stored.measuredAt,
            bandwidthKbps: stored.bandwidth?.kbps,
            bandwidthMeasuredAt: stored.bandwidth?.measuredAt,
            bandwidthRttMs: stored.bandwidth?.roundTripMs
        )
    }
}
