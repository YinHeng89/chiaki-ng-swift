import ChiakiModels
import Foundation
import Testing

@Suite struct FolderAccessTests {
    @Test func aFolderWithoutABookmarkIsUsedByItsPathAlone() {
        #expect(!FolderAccess.open("/tmp/chiaki-ng-no-bookmark", bookmark: nil))
    }

    @Test func aDamagedBookmarkGrantsNothing() {
        #expect(!FolderAccess.open("/tmp/chiaki-ng-damaged-bookmark", bookmark: Data([0, 1, 2, 3])))
    }

    #if os(macOS)
        @Test func aChosenFolderGetsABookmarkThatResolvesToIt() throws {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("chiaki-ng-folder-access-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: folder)
            }
            let bookmark = try #require(FolderAccess.bookmark(for: folder))
            var stale = false
            let resolved = try URL(
                resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            #expect(resolved.standardizedFileURL.resolvingSymlinksInPath().path
                == folder.standardizedFileURL.resolvingSymlinksInPath().path)
        }
    #endif
}
