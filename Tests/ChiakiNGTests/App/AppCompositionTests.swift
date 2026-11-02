import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation
import Testing
@testable import ChiakiNG

@MainActor @Suite struct AppCompositionTests {
    private let app = HostProcess(environment: [:], name: "ChiakiNG", bundles: [], hasTestRuntime: false)

    @Test func theAppsStorageLogsAndCatalogStayInScratchSpaceUnderTest() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let composition = TestComposition.scratch
        let data = composition.userData
        #expect(data == UserData.current)
        #expect(data.keys == .memory)
        _ = try await composition.accounts.storage()
        #expect(FileManager.default.fileExists(atPath: data.database.path))
        #expect(FileManager.default.fileExists(atPath: data.catalog.path))
        let settings = try await composition.logging.load()
        for path in [data.database.path, data.catalog.path, settings.directory] {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            #expect(!resolved.hasPrefix("\(home)/Library"))
            #expect(path.hasPrefix(FileManager.default.temporaryDirectory.path))
        }
        #expect(throws: PersistenceError.refusedLiveData) {
            try KeySource.keychain()
        }
    }

    @Test func userDataPointsTheCompositionAtTheGivenFolderAndNeverAtTheLiveOne() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-data-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let option = try UserDataArgument(arguments: ["ChiakiNG", "--user-data", folder.path, "--list"])
        let composition = try AppComposition(
            userData: option.location(in: app),
            database: AppDatabaseClient()
        )
        let live = try UserData.live(in: app)
        let data = composition.userData
        #expect(option.remaining == ["ChiakiNG", "--list"])
        #expect(data.support.path == folder.path)
        #expect(data.database.path == folder.appendingPathComponent("profiles.sqlite").path)
        #expect(data.catalog.path == folder.appendingPathComponent("Catalog", isDirectory: true).path)
        for url in [data.support, data.database, data.catalog] {
            #expect(!url.path.hasPrefix(live.support.path))
        }
        #expect(data.logs == live.logs)
        #expect(data.caches == live.caches)
        #expect(data.keys == .keychain)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func userDataIsRefusedInATestProcess() throws {
        let option = try UserDataArgument(arguments: ["ChiakiNG", "--user-data=/tmp/clone"])
        #expect(throws: UserData.Refusal.harnessProcess) {
            try option.location()
        }
    }

    @Test func installingTheCompositionHandsEveryReaderTheSameAccountService() {
        let composition = AppComposition(userData: .scratch(), database: AppDatabaseClient())
        var values = DependencyValues()
        composition.install(into: &values)
        #expect(values.accountService === composition.accounts)
        #expect(values.streamLeases === composition.streamLeases)
    }
}
