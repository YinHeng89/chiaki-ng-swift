@testable import ChiakiClientsLive
import ChiakiModels
import ChiakiPersistence
import Foundation
import Testing

@Suite struct AppDatabaseClientTests {
    @Test func theLiveClientOpensAScratchDatabaseThatTheOpenMachineAccepts() async throws {
        let data = UserData.scratch()
        defer {
            try? FileManager.default.removeItem(at: data.support.deletingLastPathComponent())
        }
        var opening = DatabaseOpening.closed
        let attempt = OperationID()
        let began = opening.begin(attempt)
        #expect(began)
        let result = await AppDatabaseClient.liveValue.open(data)
        let failure: DatabaseOpenFailure? =
            switch result {
            case .success:
                nil
            case .failure(let failure):
                failure
            }
        #expect(failure == nil)
        let finished = opening.finish(attempt, failure: failure)
        #expect(finished)
        #expect(opening == .open)
        #expect(FileManager.default.fileExists(atPath: data.database.path))
    }

    @Test func everyPersistenceErrorMapsToTheFailureTheOpenMachineRecords() {
        let expected: [(PersistenceError, DatabaseOpenFailure)] = [
            (.unsupportedVersion(found: 99, supported: 12), .unsupportedVersion),
            (.invalidMigrations, .corrupt),
            (.corruptData, .corrupt),
            (.missingKey, .keyUnavailable),
            (.keyUnavailable(status: -25300), .keyUnavailable),
            (.refusedLiveData, .refusedLiveData),
            (.database(code: 14), .unavailable),
            (.invalidInput, .unavailable),
            (.location, .unavailable)
        ]
        for (error, failure) in expected {
            #expect(AppDatabaseClient.failure(of: error) == failure)
        }
    }
}
