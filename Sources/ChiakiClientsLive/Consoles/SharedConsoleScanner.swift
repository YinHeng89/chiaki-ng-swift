import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture
import Dependencies
import Foundation
import Network

extension SharedConsoleScanner {
    /// The one scan the live `ChiakiClients/ConsolesClient` shares, over the live discovery, settings,
    /// address cache and saved pairings.
    static let shared: SharedConsoleScanner = {
        @Dependency(\.discovery) var discovery
        @Dependency(\.settings) var settings
        @Dependency(\.consoleLocations) var locations
        @Dependency(\.consoles) var registry
        return SharedConsoleScanner(
            scan: discovery.scan,
            settings: {
                try await settings.load(DiscoverySettings.self)
            },
            cache: { consoles, reported in
                do {
                    return try await locations.cache(consoles, reported)
                } catch {
                    @Dependency(\.logger) var logger
                    await logger.log(.consoleWarning(
                        "Discovery: saving the LAN addresses of \(consoles.count) discovered consoles failed: "
                            + LogFormat.error(error)
                    ))
                    return false
                }
            },
            catalogChanged: registry.notePairingsChanged,
            clock: ContinuousClock()
        )
    }()
}

/// The one local-network console scan, shared by every subscriber.
///
/// The scan starts with the first subscriber and stops when the last one leaves. Each new snapshot is sent to
/// every subscriber and the addresses of consoles that changed are saved once. Every
/// ``monitorInterval`` the settings are read again: changed settings restart the scan, and the current
/// consoles' addresses are saved again so a pairing made meanwhile picks them up. A saved address is reported
/// through `catalogChanged`. A scan that ends or cannot read its settings reports
/// `ConsoleScanEvent/failed`; the next subscription starts it again.
actor SharedConsoleScanner {
    /// How often the settings are re-read and the addresses saved again.
    static let monitorInterval: Duration = .seconds(2)

    private enum Ending: Sendable {
        case settingsChanged
        case scanEnded
        case cancelled
    }

    private let scan: @Sendable (DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, Error>
    private let settings: @Sendable () async throws -> DiscoverySettings
    private let cache: @Sendable ([DiscoveredConsole], Set<String>) async -> Bool
    private let catalogChanged: @Sendable () -> Void
    private let clock: any Clock<Duration>
    private var subscribers: [UUID: AsyncStream<ConsoleScanEvent>.Continuation] = [:]
    private var running: (token: UUID, task: Task<Void, Never>)?
    private var latest: DiscoverySnapshot?

    /// Creates a scanner that is not scanning.
    ///
    /// - Parameters:
    ///   - scan: Scans with settings until cancelled.
    ///   - settings: Reads the current discovery settings.
    ///   - cache: Saves the addresses of consoles, reporting the ids in the set; returns whether any changed.
    ///   - catalogChanged: Reports that a saved address changed the pairings.
    ///   - clock: The clock the settings are re-read on.
    init(
        scan: @escaping @Sendable (DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, Error>,
        settings: @escaping @Sendable () async throws -> DiscoverySettings,
        cache: @escaping @Sendable ([DiscoveredConsole], Set<String>) async -> Bool,
        catalogChanged: @escaping @Sendable () -> Void,
        clock: any Clock<Duration>
    ) {
        self.scan = scan
        self.settings = settings
        self.cache = cache
        self.catalogChanged = catalogChanged
        self.clock = clock
    }

    /// Subscribes to the scan, starting it when nothing else is subscribed.
    ///
    /// - Returns: The scan's events, starting with the latest snapshot when one is known. Ending the iteration
    ///   unsubscribes.
    func events() -> AsyncStream<ConsoleScanEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ConsoleScanEvent.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.unsubscribe(id)
            }
        }
        subscribers[id] = continuation
        if let latest {
            continuation.yield(.snapshot(latest))
        }
        if running == nil {
            let token = UUID()
            running = (token, Task {
                await self.scanUntilStopped(token)
            })
        }
        return stream
    }

    /// The number of subscribers.
    var subscriberCount: Int {
        subscribers.count
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        guard subscribers.isEmpty else {
            return
        }
        running?.task.cancel()
        running = nil
        latest = nil
    }

    private func scanUntilStopped(_ token: UUID) async {
        while !Task.isCancelled {
            let value: DiscoverySettings
            do {
                value = try await settings()
            } catch {
                fail(token)
                return
            }
            guard !Task.isCancelled else {
                return
            }
            let ending = await withTaskGroup(of: Ending.self) { group in
                group.addTask {
                    await self.follow(value)
                }
                group.addTask {
                    await self.monitor(value)
                }
                let first = await group.next() ?? .cancelled
                group.cancelAll()
                return first
            }
            switch ending {
            case .settingsChanged:
                guard running?.token == token else {
                    return
                }
                latest = nil
                continue
            case .scanEnded:
                fail(token)
                return
            case .cancelled:
                return
            }
        }
    }

    private func follow(_ value: DiscoverySettings) async -> Ending {
        do {
            for try await snapshot in scan(value) {
                guard !Task.isCancelled else {
                    return .cancelled
                }
                await receive(snapshot)
            }
        } catch {
            return Task.isCancelled
                ? .cancelled
                : .scanEnded
        }
        return Task.isCancelled
            ? .cancelled
            : .scanEnded
    }

    private func monitor(_ value: DiscoverySettings) async -> Ending {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: Self.monitorInterval)
            } catch {
                return .cancelled
            }
            if let current = try? await settings(), current != value {
                return .settingsChanged
            }
            let consoles = latest?.consoles ?? []
            if !consoles.isEmpty, await cache(consoles, []) {
                catalogChanged()
            }
        }
        return .cancelled
    }

    private func receive(_ snapshot: DiscoverySnapshot) async {
        let previous = latest?.consoles ?? []
        latest = snapshot
        for continuation in subscribers.values {
            continuation.yield(.snapshot(snapshot))
        }
        let lost = previous.filter { old in
            !snapshot.consoles.contains { $0.id == old.id }
        }
        if !lost.isEmpty {
            @Dependency(\.logger) var logger
            for console in lost {
                await logger.log(.consoleDiagnostic(
                    "Discovery: \(console.kind.rawValue) \"\(console.name)\" MAC \(console.id) at "
                        + "\(console.address) stopped answering for 10 s and was removed from the list"
                ))
            }
        }
        let changed = Set(snapshot.consoles.filter { console in
            previous.first { $0.id == console.id }.map {
                $0.address != console.address || $0.standby != console.standby || $0.name != console.name
            } ?? true
        }.map(\.id))
        if await cache(snapshot.consoles, changed) {
            catalogChanged()
        }
    }

    private func fail(_ token: UUID) {
        guard running?.token == token else {
            return
        }
        running = nil
        latest = nil
        for continuation in subscribers.values {
            continuation.yield(.failed)
        }
    }
}

/// Scans the local network for consoles and streams what it finds.
public struct DiscoveryClient: Sendable {
    /// Starts a scan with the given settings and yields each updated set of discovered consoles.
    public var scan: @Sendable (DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, Error>
    /// Creates a client over a scan closure.
    ///
    /// - Parameter scan: Starts a scan and streams its snapshots.
    public init(
        scan:
        @escaping @Sendable (DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, Error>
    ) {
        self.scan = scan
    }

    /// A client backed by the core's discovery. It keeps only the newest snapshot, logs the error that stops
    /// a scan, and cancels the scan when the stream ends.
    ///
    /// - Parameter logger: Receives the diagnostic logged when a scan stops.
    /// - Returns: The client.
    public static func live(logger: LoggerClient = .disabled) -> Self {
        .init { settings in
            AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                let task = Task {
                    do {
                        for try await snapshot in DiscoveryBridge().scan(settings) {
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                    } catch {
                        await logger.log(.diagnostic(
                            .discovery, .error,
                            "Stopped: \(LogFormat.error(error)); "
                                + "the console list stops updating until discovery restarts"
                        ))
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }
}

extension DiscoveryClient: DependencyKey {
    /// Scans the local network through the core.
    public static var liveValue: DiscoveryClient {
        @Dependency(\.logger) var logger
        return .live(logger: logger)
    }

    /// A scan that ends at once.
    public static let testValue = DiscoveryClient { _ in
        AsyncThrowingStream {
            $0.finish()
        }
    }
}

extension DependencyValues {
    /// The core's local-network scan, which the live `ChiakiClients/ConsolesClient` shares.
    public var discovery: DiscoveryClient {
        get {
            self[DiscoveryClient.self]
        }
        set {
            self[DiscoveryClient.self] = newValue
        }
    }
}

/// Saves the addresses discovered consoles answer from as the addresses of their pairings.
public struct ConsoleLocationClient: Sendable {
    /// Saves the consoles' addresses, logging the ones whose ids are in the set; returns whether any changed.
    public var cache: @Sendable ([DiscoveredConsole], Set<String>) async throws -> Bool

    /// Creates a client.
    ///
    /// - Parameter cache: Saves the addresses.
    public init(cache: @escaping @Sendable ([DiscoveredConsole], Set<String>) async throws -> Bool) {
        self.cache = cache
    }
}

extension ConsoleLocationClient: DependencyKey {
    /// Saves addresses in the app's database.
    public static let liveValue = ConsoleLocationClient { consoles, reported in
        @Dependency(\.accountService) var accountService
        let repository = try await accountService.storage()
        var saved = false
        @Dependency(\.logger) var logger
        for console in consoles {
            let report = reported.contains(console.id)
            let power = console.standby
                ? "standby"
                : "awake"
            let found = "Discovery: \(console.kind.rawValue) \"\(console.name)\" MAC \(console.id) at "
                + "\(console.address) (\(power))"
            guard let hardware = HardwareID(hex: console.id), IPv4Address(console.address) != nil else {
                throw PersistenceError.invalidInput
            }
            switch try repository.consoles.rememberAddress(console.address, of: hardware) {
            case .updated(let previous):
                saved = true
                await logger.log(.consoleDiagnostic(
                    "\(found): saved as the LAN address of the registered console, previously "
                        + (previous ?? "none")
                ))
            case .unchanged where report:
                await logger.log(.consoleDiagnostic("\(found): matches the saved LAN address"))
            case .unregistered where report:
                await logger.log(.consoleDiagnostic(
                    "\(found): no registered console has this MAC, nothing saved"
                ))
            case .unchanged, .unregistered:
                break
            }
        }
        return saved
    }

    /// Saves nothing.
    public static let testValue = ConsoleLocationClient { _, _ in
        false
    }
}

extension DependencyValues {
    /// Saves discovered consoles' addresses.
    public var consoleLocations: ConsoleLocationClient {
        get {
            self[ConsoleLocationClient.self]
        }
        set {
            self[ConsoleLocationClient.self] = newValue
        }
    }
}
