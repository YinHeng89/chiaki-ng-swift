import ChiakiModels
import Foundation
import GRDB

/// The PS5 cloud captures waiting to be saved to this device, in the `cloud_capture_downloads` table.
///
/// A capture is queued when the console reports its upload and removed once it was saved or given up, so a
/// save interrupted by quitting is finished on the next launch.
public final class CloudCaptureRepository: Sendable {
    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// Queues a capture to save; a capture already queued is left as it is.
    ///
    /// - Parameters:
    ///   - capture: The capture.
    ///   - now: When it is queued.
    /// - Throws: ``PersistenceError/invalidInput`` when the capture has no gallery id or its folder has no path.
    public func queue(_ capture: PendingCloudCapture, now: Date = Date()) throws(PersistenceError) {
        guard !capture.upload.galleryID.isEmpty, !capture.folder.path.isEmpty else {
            throw .invalidInput
        }
        try database.write { database in
            try database.execute(
                sql: CloudCaptureDownloadRow.insert,
                arguments: CloudCaptureDownloadRow.insertArguments(capture, now: now)
            )
        }
    }

    /// Every capture still waiting to be saved, oldest first.
    ///
    /// - Returns: The captures.
    /// - Throws: ``PersistenceError/corruptData`` when a row's account id is not eight bytes, or a database
    ///   error.
    public func pending() throws(PersistenceError) -> [PendingCloudCapture] {
        let rows = try database.read { database in
            try CloudCaptureDownloadRow.fetchAll(database, sql: CloudCaptureDownloadRow.selectAll)
        }
        return try rows.map { row throws(PersistenceError) in
            guard let capture = row.capture else {
                throw .corruptData
            }
            return capture
        }
    }

    /// Counts one more failed save of a capture.
    ///
    /// - Parameter galleryID: The capture's gallery id.
    /// - Throws: A database error.
    public func noteAttempt(galleryID: String) throws(PersistenceError) {
        try database.write { database in
            try database.execute(sql: CloudCaptureDownloadRow.noteAttempt, arguments: [galleryID])
        }
    }

    /// Forgets a capture that was saved or given up.
    ///
    /// - Parameter galleryID: The capture's gallery id.
    /// - Throws: A database error.
    public func finish(galleryID: String) throws(PersistenceError) {
        try database.write { database in
            try database.execute(sql: CloudCaptureDownloadRow.delete, arguments: [galleryID])
        }
    }
}

/// One row of the `cloud_capture_downloads` table, decoded by column name.
private struct CloudCaptureDownloadRow: FetchableRecord, Sendable {
    /// Queues a capture once; a capture already queued keeps its attempts.
    static let insert = """
    INSERT OR IGNORE INTO cloud_capture_downloads(gallery_id, account_id, title, file_extension, video, created,
        folder, attempts, queued_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
    """

    /// Selects every queued capture, oldest first.
    static let selectAll = """
    SELECT gallery_id, account_id, title, file_extension, video, created, folder, attempts
    FROM cloud_capture_downloads ORDER BY queued_at, gallery_id
    """

    /// Counts one more failed save of a capture.
    static let noteAttempt = "UPDATE cloud_capture_downloads SET attempts = attempts + 1 WHERE gallery_id = ?"

    /// Removes a capture that was saved or given up.
    static let delete = "DELETE FROM cloud_capture_downloads WHERE gallery_id = ?"

    /// The capture the row holds, or `nil` when its account id is not eight bytes.
    let capture: PendingCloudCapture?

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectAll``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        guard let account = try AccountID(bytes: row.decode(Data.self, forColumn: "account_id")) else {
            capture = nil
            return
        }
        let gallery = try row.decode(String.self, forColumn: "gallery_id")
        let created = try row.decode(Int64?.self, forColumn: "created")
        capture = try PendingCloudCapture(
            upload: CloudCaptureUpload(
                id: gallery,
                galleryID: gallery,
                fileExtension: row.decode(String.self, forColumn: "file_extension"),
                size: 0,
                video: row.decode(Int64.self, forColumn: "video") == 1,
                created: created.map(Timestamp.date(milliseconds:))
            ),
            account: account,
            title: row.decode(String.self, forColumn: "title"),
            folder: URL(fileURLWithPath: row.decode(String.self, forColumn: "folder"), isDirectory: true),
            attempts: Int(row.decode(Int64.self, forColumn: "attempts"))
        )
    }

    /// The arguments of ``insert`` for one capture.
    ///
    /// - Parameters:
    ///   - capture: The capture.
    ///   - now: When it is queued.
    /// - Returns: The statement arguments.
    static func insertArguments(_ capture: PendingCloudCapture, now: Date) -> StatementArguments {
        [
            capture.upload.galleryID,
            capture.account.data,
            capture.title,
            capture.upload.fileExtension,
            capture.upload.video
                ? Int64(1)
                : Int64(0),
            capture.upload.created.map(Timestamp.milliseconds(of:)),
            capture.folder.path,
            Timestamp.milliseconds(of: now)
        ]
    }
}
