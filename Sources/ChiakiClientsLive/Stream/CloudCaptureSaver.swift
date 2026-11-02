import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

/// Saves screenshots and clips a PS5 cloud console uploaded to the account's gallery into a folder on this
/// Mac, or into the Photos library on iOS.
///
/// Every capture is remembered in the database before it is fetched, so a save interrupted by quitting is
/// finished on the next launch by ``resume()``. A save that fails, usually because a clip is still being
/// processed, is tried again during the session after ``resaveDelay(afterAttempts:)``, and a capture whose save
/// keeps failing is given up after ``maximumAttempts``. A wait for the next save belongs to the saver and is
/// cancelled when the saver is released. The composition root builds the one instance over the
/// app's account service.
public actor CloudCaptureSaver {
    /// How many failed saves a capture is given before it is dropped.
    static let maximumAttempts = 8

    /// The longest wait before saving a capture again during the session.
    static let longestResaveDelay = Duration.seconds(240)

    /// How long to wait before saving a capture again during the session: 30 seconds after the first failure,
    /// doubling up to ``longestResaveDelay``.
    ///
    /// - Parameter attempts: How many saves of the capture have failed.
    /// - Returns: The wait before the next save.
    static func resaveDelay(afterAttempts attempts: Int) -> Duration {
        min(.seconds(30) * (1 << min(max(attempts - 1, 0), 3)), longestResaveDelay)
    }

    /// How many times one save asks PSN for the capture before counting a failed attempt.
    static let fetchAttempts = 3

    /// How long a save waits between asking PSN again.
    static let retryDelay = Duration.seconds(3)

    /// How long the account's PlayStation capture setting is trusted before it is read again.
    static let settingRemembered: TimeInterval = 300

    private struct RememberedSetting {
        let downloads: Bool
        let readAt: Date
    }

    private let accounts: AccountService
    private let catalog: CatalogBridge
    private var running: Set<String> = []
    private var settings: [AccountID: RememberedSetting] = [:]
    private var resaves: [String: Task<Void, Never>] = [:]

    /// Creates the saver over the app's accounts.
    ///
    /// - Parameters:
    ///   - accounts: The account service whose database remembers the captures to save.
    ///   - catalog: The core's catalog, which finds each capture's download address.
    public init(accounts: AccountService, catalog: CatalogBridge = CatalogBridge()) {
        self.accounts = accounts
        self.catalog = catalog
    }

    deinit {
        for resave in resaves.values {
            resave.cancel()
        }
    }

    /// Saves a capture the console just uploaded.
    ///
    /// - Parameters:
    ///   - capture: The capture.
    ///   - followsPlayStation: Whether to save only when the account's PlayStation setting downloads
    ///     captures.
    public func save(_ capture: PendingCloudCapture, followsPlayStation: Bool) async {
        if followsPlayStation, await !playStationDownloads(account: capture.account) {
            return
        }
        do {
            try await accounts.storage().captures.queue(capture)
        } catch {
            await log(.warning, "Could not remember a cloud capture to save: \(error)")
        }
        await run(capture)
    }

    /// Saves every capture left from an earlier launch.
    public func resume() async {
        let pending: [PendingCloudCapture]
        do {
            pending = try await accounts.storage().captures.pending()
        } catch {
            await log(.warning, "Could not read the cloud captures left to save: \(error)")
            return
        }
        guard !pending.isEmpty else {
            return
        }
        await log(.info, "Saving \(pending.count) cloud captures left from before")
        for capture in pending {
            await run(capture)
        }
    }

    private func run(_ capture: PendingCloudCapture) async {
        let gallery = capture.upload.galleryID
        guard running.insert(gallery).inserted else {
            return
        }
        defer {
            running.remove(gallery)
        }
        do throws(CloudCaptureDownloadFailure) {
            let saved = try await fetch(capture)
            try? await accounts.storage().captures.finish(galleryID: gallery)
            await log(.info, "Saved a cloud capture as \(saved)")
        } catch .signInRequired {
            await log(.warning, "A cloud capture waits to be saved until the account signs in again")
        } catch .photos(denied: true) {
            await log(.warning, "A cloud capture waits to be saved until chiaki-ng may add to Photos")
        } catch {
            await giveUpIfExhausted(capture, failure: error)
        }
    }

    private func fetch(_ capture: PendingCloudCapture) async throws(CloudCaptureDownloadFailure) -> String {
        var lastFailure = CloudCaptureDownloadFailure.notFound
        for attempt in 1...Self.fetchAttempts {
            do throws(CloudCaptureDownloadFailure) {
                let file = try await locate(capture)
                return try await store(file, capture: capture)
            } catch .signInRequired {
                throw .signInRequired
            } catch .photos(denied: true) {
                throw .photos(denied: true)
            } catch {
                lastFailure = error
            }
            if attempt < Self.fetchAttempts {
                do {
                    try await Task.sleep(for: Self.retryDelay)
                } catch {
                    throw lastFailure
                }
            }
        }
        throw lastFailure
    }

    private func locate(_ capture: PendingCloudCapture) async throws(CloudCaptureDownloadFailure)
        -> CloudCaptureFile {
        let found: CloudCaptureFile?
        do {
            found = try await catalog.cloudCapture(
                account: capture.account,
                galleryID: capture.upload.galleryID
            )
        } catch {
            throw error.needsSignIn
                ? .signInRequired
                : .notFound
        }
        guard let found else {
            throw .notFound
        }
        return found
    }

    private func store(
        _ file: CloudCaptureFile,
        capture: PendingCloudCapture
    ) async throws(CloudCaptureDownloadFailure) -> String {
        let downloaded: URL
        let response: URLResponse
        let signed = !(file.url.query ?? "").isEmpty
        do {
            (downloaded, response) = try await URLSession.shared.download(from: file.url)
        } catch {
            throw .transfer(status: 0, signed: signed)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: downloaded)
            throw .transfer(status: status, signed: signed)
        }
        let upload = capture.upload
        let name = CloudCaptureFileName(
            title: capture.title,
            created: upload.created ?? Date(),
            fileExtension: upload.fileExtension.isEmpty
                ? file.fileType
                : upload.fileExtension,
            video: upload.video
        )
        #if os(iOS)
            try await CloudCapturePhotos.add(downloaded, name: name, video: upload.video)
            return "\(name.value) in Photos"
        #else
            do {
                try FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
                let destination = Self.available(capture.folder.appendingPathComponent(name.value))
                try FileManager.default.moveItem(at: downloaded, to: destination)
                return destination.lastPathComponent
            } catch {
                try? FileManager.default.removeItem(at: downloaded)
                throw .folder
            }
        #endif
    }

    private func resave(_ gallery: String) async {
        resaves[gallery] = nil
        guard let pending = try? await accounts.storage().captures.pending(),
              let capture = pending.first(where: { $0.upload.galleryID == gallery }) else {
            return
        }
        await run(capture)
    }

    private func giveUpIfExhausted(
        _ capture: PendingCloudCapture,
        failure: CloudCaptureDownloadFailure
    ) async {
        let gallery = capture.upload.galleryID
        let attempts = capture.attempts + 1
        guard attempts >= Self.maximumAttempts else {
            try? await accounts.storage().captures.noteAttempt(galleryID: gallery)
            let delay = Self.resaveDelay(afterAttempts: attempts)
            await log(
                .warning,
                "Could not save a cloud capture yet (\(failure)); trying again in \(delay.components.seconds) s"
            )
            resaves[gallery]?.cancel()
            resaves[gallery] = Task { [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                await self?.resave(gallery)
            }
            return
        }
        try? await accounts.storage().captures.finish(galleryID: gallery)
        await log(.warning, "Gave up saving a cloud capture after \(attempts) attempts: \(failure)")
    }

    private func playStationDownloads(account: AccountID) async -> Bool {
        if let remembered = settings[account],
           Date().timeIntervalSince(remembered.readAt) < Self.settingRemembered {
            return remembered.downloads
        }
        do {
            let downloads = try await catalog.cloudCaptureDownload(account: account)
            settings[account] = RememberedSetting(downloads: downloads, readAt: Date())
            let verdict = downloads
                ? "downloads"
                : "keeps"
            await log(.info, "The PlayStation capture setting \(verdict) captures")
            return downloads
        } catch {
            await log(
                .warning,
                "Could not read the PlayStation capture setting (\(error)); saving captures anyway"
            )
            return true
        }
    }

    private func log(_ level: LogLevel, _ message: String) async {
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(.cloud, level, message))
    }

    private static func available(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }
        let base = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension
        let folder = url.deletingLastPathComponent()
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(suffix)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            number += 1
        }
    }
}
