import Foundation
import Synchronization

/// Where this installation keeps its database, catalog, logs and caches, and where its encryption key lives.
///
/// The app installs one location at launch with ``install(_:)``. A test process never reaches the live
/// location: ``live(in:)`` refuses a harness, and ``current`` falls back to a fresh ``scratch()`` location
/// with an in-memory key.
public struct UserData: Equatable, Sendable {
    /// Where the credential encryption key is kept.
    public enum Keys: Equatable, Sendable {
        /// In the login Keychain.
        case keychain

        /// In process memory only, for scratch locations.
        case memory
    }

    /// Why a live location was refused.
    public enum Refusal: Error, Equatable, Sendable {
        /// The process is a test harness or preview host.
        case harnessProcess
    }

    /// The Application Support folder that holds the database and catalog.
    public let support: URL

    /// The folder log files are written to.
    public let logs: URL

    /// The folder for caches that can be rebuilt.
    public let caches: URL

    /// Where the encryption key is kept.
    public let keys: Keys

    /// The SQLite database file.
    public var database: URL {
        support.appendingPathComponent("profiles.sqlite")
    }

    /// The folder the core keeps its catalog records in.
    public var catalog: URL {
        support.appendingPathComponent("Catalog", isDirectory: true)
    }

    private init(support: URL, logs: URL, caches: URL, keys: Keys) {
        self.support = support
        self.logs = logs
        self.caches = caches
        self.keys = keys
    }

    /// The user's real location under their Library folder, with the key in the Keychain.
    ///
    /// - Parameter process: The process asking.
    /// - Returns: The live location.
    /// - Throws: ``Refusal/harnessProcess`` when `process` is a harness, or the error `FileManager` reports
    ///   when a Library folder cannot be resolved.
    public static func live(in process: HostProcess = .current) throws -> Self {
        guard !process.isHarness else {
            throw Refusal.harnessProcess
        }
        let files = FileManager.default
        return Self(
            support: try files.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent(AppIdentity.bundleIdentifier, isDirectory: true),
            logs: try files.url(
                for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent("Logs/\(AppIdentity.bundleIdentifier)", isDirectory: true),
            caches: try files.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent(AppIdentity.bundleIdentifier, isDirectory: true),
            keys: .keychain
        )
    }

    /// The user's real location with the database and catalog moved to another folder, for the
    /// `--user-data` launch option.
    ///
    /// - Parameters:
    ///   - support: The folder that holds the database and the `Catalog` folder.
    ///   - process: The process asking.
    /// - Returns: The live location with ``support`` replaced.
    /// - Throws: The error ``live(in:)`` throws.
    public static func directory(_ support: URL, in process: HostProcess = .current) throws -> Self {
        let live = try live(in: process)
        return Self(support: support, logs: live.logs, caches: live.caches, keys: live.keys)
    }

    /// A fresh location under the temporary directory, with the key in memory.
    ///
    /// - Returns: A location no other call shares.
    public static func scratch() -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(AppIdentity.name)-scratch-\(UUID().uuidString)", isDirectory: true
        )
        return Self(
            support: root.appendingPathComponent("Support", isDirectory: true),
            logs: root.appendingPathComponent("Logs", isDirectory: true),
            caches: root.appendingPathComponent("Caches", isDirectory: true),
            keys: .memory
        )
    }

    private static let installed = Mutex<UserData?>(nil)

    /// Makes `data` the location ``current`` returns for the rest of the process.
    ///
    /// - Parameter data: The location the app's entry point chose.
    public static func install(_ data: UserData) {
        installed.withLock {
            $0 = data
        }
    }

    /// The installed location, or a scratch location in a harness that installed none.
    public static var current: UserData {
        installed.withLock { value in
            if let value {
                return value
            }
            guard HostProcess.current.isHarness else {
                fatalError("The app's entry point never installed the user data location")
            }
            let data = scratch()
            value = data
            return data
        }
    }
}
