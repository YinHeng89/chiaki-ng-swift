import ChiakiModels
import Foundation
import Testing

@Suite struct LogLevelTests {
    @Test func prioritiesAreExplicitAndOrdered() {
        #expect(LogLevel.allCases.map(\.priority) == [0, 1, 2, 3, 4])
    }

    @Test func aLevelAdmitsOnlyEventsNoMoreVerboseThanItself() {
        #expect(LogLevel.info.admits(.error))
        #expect(LogLevel.info.admits(.info))
        #expect(!LogLevel.info.admits(.debug))
        #expect(!LogLevel.off.admits(.error))
        #expect(!LogLevel.debug.admits(.off))
    }

    @Test func settingsFromAnOlderVersionDecodeWithDefaults() throws {
        let stored = Data(#"{"directory":"/tmp/logs","level":"warning"}"#.utf8)
        let settings = try JSONDecoder().decode(LogSettings.self, from: stored)
        #expect(settings.level == .warning)
        #expect(settings.redactIdentifiers)
        #expect(!settings.captureAPI && !settings.showLiveLogButton && !settings.streamerMode)
        #expect(settings.directoryBookmark == nil)
    }

    @Test func aChosenFoldersBookmarkIsKeptWithItsPath() throws {
        var settings = LogSettings(directory: "/tmp/logs")
        settings.directoryBookmark = Data([1, 2, 3])
        let decoded = try JSONDecoder().decode(LogSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.directory == "/tmp/logs")
        #expect(decoded.directoryBookmark == Data([1, 2, 3]))
    }
}
