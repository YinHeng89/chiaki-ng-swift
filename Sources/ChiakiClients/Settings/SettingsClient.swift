import ChiakiModels
import ComposableArchitecture
import Foundation

/// Reaches the settings: loads and saves any `ChiakiModels/PersistedSettingValue` by its key, reads what this
/// build and this Mac offer the settings panes, and reads and manages the core's HTTP request log.
///
/// The one store every settings pane uses. The store's interface is type erased so that one dependency serves
/// every value type; ``load(_:)`` and ``save(_:)`` restore the types and validate the value on its way in and
/// out.
public struct SettingsClient: Sendable {
    /// Reads the stored value of a type, or its key's default when nothing is stored.
    public var read: @Sendable (_ type: any PersistedSettingValue.Type) async throws(PersistedSettingFailure)
        -> any PersistedSettingValue

    /// Writes a validated value under its type's key.
    public var write: @Sendable (_ value: any PersistedSettingValue) async throws(PersistedSettingFailure)
        -> Void

    /// Returns the Takion version this build negotiates for a connection kind left automatic.
    public var buildTakionVersion: @Sendable (TakionTarget) -> UInt32

    /// Lists the connected audio output and input devices.
    public var soundDevices: @Sendable () async -> SoundDevices

    /// Returns the request log's current revision, which changes whenever an exchange is recorded or the log
    /// is cleared.
    public var requestLogRevision: @Sendable () async -> UInt64

    /// Reads the recorded exchanges and per base totals of the request log.
    public var requestLog: @Sendable () async throws -> CoreHTTPLog

    /// Reads the headers and bodies of one recorded exchange, or `nil` when it is no longer kept.
    public var requestDetail: @Sendable (UInt64) async -> CoreHTTPExchangeDetail?

    /// Removes every recorded exchange from the request log.
    public var clearRequestLog: @Sendable () async -> Void

    /// Resets the lifetime request totals.
    public var resetRequestTotals: @Sendable () async -> Void

    /// Returns the version and commit the linked core was built as.
    public var coreBuild: @Sendable () async -> CoreBuild

    /// Creates a client from its operations; only the store's two are required.
    ///
    /// - Parameters:
    ///   - read: Reads the stored value of a type.
    ///   - write: Writes a value under its type's key.
    ///   - buildTakionVersion: Returns the Takion version this build negotiates for a connection kind left
    ///     automatic; by default no build version.
    ///   - soundDevices: Lists the connected audio devices; by default none.
    ///   - requestLogRevision: Returns the request log's revision; by default zero.
    ///   - requestLog: Reads the request log; by default an empty one.
    ///   - requestDetail: Reads one exchange's details; by default none.
    ///   - clearRequestLog: Clears the request log; by default nothing.
    ///   - resetRequestTotals: Resets the lifetime request totals; by default nothing.
    ///   - coreBuild: Returns the core's build; by default one with no version or commit.
    public init(
        read: @escaping @Sendable (_ type: any PersistedSettingValue
            .Type) async throws(PersistedSettingFailure)
            -> any PersistedSettingValue,
        write: @escaping @Sendable (_ value: any PersistedSettingValue) async throws(PersistedSettingFailure)
            -> Void,
        buildTakionVersion: @escaping @Sendable (TakionTarget) -> UInt32 = { _ in
            0
        },
        soundDevices: @escaping @Sendable () async -> SoundDevices = {
            SoundDevices()
        },
        requestLogRevision: @escaping @Sendable () async -> UInt64 = {
            0
        },
        requestLog: @escaping @Sendable () async throws -> CoreHTTPLog = {
            CoreHTTPLog()
        },
        requestDetail: @escaping @Sendable (UInt64) async -> CoreHTTPExchangeDetail? = { _ in
            nil
        },
        clearRequestLog: @escaping @Sendable () async -> Void = {
        },
        resetRequestTotals: @escaping @Sendable () async -> Void = {
        },
        coreBuild: @escaping @Sendable () async -> CoreBuild = {
            CoreBuild(version: "", commit: "")
        }
    ) {
        self.read = read
        self.write = write
        self.buildTakionVersion = buildTakionVersion
        self.soundDevices = soundDevices
        self.requestLogRevision = requestLogRevision
        self.requestLog = requestLog
        self.requestDetail = requestDetail
        self.clearRequestLog = clearRequestLog
        self.resetRequestTotals = resetRequestTotals
        self.coreBuild = coreBuild
    }

    /// Loads a setting.
    ///
    /// - Parameter type: The setting's type.
    /// - Returns: The stored value, or the key's default when nothing is stored.
    /// - Throws: `ChiakiModels/PersistedSettingFailure/unavailable` when the storage cannot be read, and
    ///   `ChiakiModels/PersistedSettingFailure/invalid` when the stored value does not validate.
    public func load<Value: PersistedSettingValue>(
        _ type: Value.Type = Value.self
    ) async throws(PersistedSettingFailure) -> Value {
        guard let value = try await read(type) as? Value else {
            throw .unavailable
        }
        return try Self.checked(value)
    }

    /// Saves a setting.
    ///
    /// - Parameter value: The value to store.
    /// - Returns: The value as stored, after validation.
    /// - Throws: `ChiakiModels/PersistedSettingFailure/invalid` when the value does not validate, and
    ///   `ChiakiModels/PersistedSettingFailure/unavailable` when it could not be written.
    @discardableResult
    public func save<Value: PersistedSettingValue>(_ value: Value) async throws(PersistedSettingFailure)
        -> Value {
        let checked = try Self.checked(value)
        try await write(checked)
        return checked
    }

    /// A store that keeps values in memory, for previews and tests, with no build version, no sound devices and
    /// an empty request log.
    ///
    /// - Parameter values: The values stored at the start.
    /// - Returns: A store that reads back what was written and defaults everything else.
    public static func inMemory(_ values: [any PersistedSettingValue] = []) -> Self {
        let stored = LockIsolated(Dictionary(
            values.map { ($0.settingName, $0) },
            uniquingKeysWith: { _, last in
                last
            }
        ))
        return Self(
            read: { type in
                stored.value[type.settingName] ?? type.defaultSetting
            },
            write: { value in
                stored.withValue {
                    $0[value.settingName] = value
                }
            }
        )
    }

    private static func checked<Value: PersistedSettingValue>(
        _ value: Value
    ) throws(PersistedSettingFailure) -> Value {
        do {
            return try value.normalized().validated()
        } catch {
            throw .invalid
        }
    }
}

extension SettingsClient: TestDependencyKey {
    /// An empty in-memory store, fresh for each test, that reads back what the test wrote.
    public static var testValue: Self {
        .inMemory()
    }

    /// An empty in-memory store for previews.
    public static var previewValue: Self {
        .inMemory()
    }
}

extension DependencyValues {
    /// Loads and saves settings, and reads what the settings panes show beside them.
    public var settings: SettingsClient {
        get {
            self[SettingsClient.self]
        }
        set {
            self[SettingsClient.self] = newValue
        }
    }
}
