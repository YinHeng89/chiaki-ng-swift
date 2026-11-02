import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct CloudCaptureRepositoryTests {
    let taken = Date(timeIntervalSince1970: 1_760_783_468)

    func screenshot() -> PendingCloudCapture {
        PendingCloudCapture(
            upload: CloudCaptureUpload(
                id: "psn1", galleryID: "psn1", fileExtension: ".jpg", size: 132_722, video: false,
                created: taken
            ),
            account: AccountID(value: 0x0807_0605_0403_0201),
            title: "Game",
            folder: URL(fileURLWithPath: "/tmp/captures", isDirectory: true)
        )
    }

    func clip() -> PendingCloudCapture {
        PendingCloudCapture(
            upload: CloudCaptureUpload(id: "psn2", galleryID: "psn2", fileExtension: "", size: 0, video: true,
                                       created: nil),
            account: AccountID(value: 9),
            title: "Other",
            folder: URL(fileURLWithPath: "/tmp/clips", isDirectory: true)
        )
    }

    @Test func capturesWaitInTheDatabaseUntilSavedAcrossReopen() throws {
        let path = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: path)
        }
        let keys = KeychainKeyStore(source: .memory())
        do {
            let captures = try CloudCaptureRepository(database: TestDatabase(path: path.path, keys: keys)
                .database)
            try captures.queue(screenshot(), now: Date(timeIntervalSince1970: 100))
            try captures.queue(screenshot(), now: Date(timeIntervalSince1970: 300))
            try captures.queue(clip(), now: Date(timeIntervalSince1970: 200))
            try captures.noteAttempt(galleryID: "psn2")
        }
        let reopened = try CloudCaptureRepository(database: TestDatabase(path: path.path, keys: keys)
            .database)
        let pending = try reopened.pending()
        #expect(pending.map(\.upload.galleryID) == ["psn1", "psn2"])
        #expect(pending[0].account == AccountID(value: 0x0807_0605_0403_0201))
        #expect(pending[0].title == "Game")
        #expect(pending[0].upload.fileExtension == ".jpg")
        #expect(!pending[0].upload.video)
        #expect(pending[0].upload.created == taken)
        #expect(pending[0].attempts == 0)
        #expect(pending[0].folder.path == "/tmp/captures")
        #expect(pending[1].upload.video)
        #expect(pending[1].upload.created == nil)
        #expect(pending[1].attempts == 1)
        try reopened.finish(galleryID: "psn1")
        #expect(try reopened.pending().map(\.upload.galleryID) == ["psn2"])
    }

    @Test func aCaptureWithoutAGalleryIDIsRefused() throws {
        let captures = try CloudCaptureRepository(database: TestDatabase().database)
        let empty = PendingCloudCapture(
            upload: CloudCaptureUpload(id: "", galleryID: "", fileExtension: "", size: 0, video: false,
                                       created: nil),
            account: AccountID(value: 1),
            title: "",
            folder: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        #expect(throws: PersistenceError.invalidInput) {
            try captures.queue(empty)
        }
        #expect(try captures.pending().isEmpty)
    }

    @Test func theTimesAreStoredAsWholeMilliseconds() throws {
        let fixture = try TestDatabase()
        let captures = CloudCaptureRepository(database: fixture.database)
        try captures.queue(screenshot(), now: Date(timeIntervalSince1970: 1_760_000_000.25))
        let queued: Int64? = try fixture.scalar("SELECT queued_at FROM cloud_capture_downloads")
        let created: Int64? = try fixture.scalar("SELECT created FROM cloud_capture_downloads")
        #expect(queued == 1_760_000_000_250)
        #expect(created == 1_760_783_468_000)
    }
}
