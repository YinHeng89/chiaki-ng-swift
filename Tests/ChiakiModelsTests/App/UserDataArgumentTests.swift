import ChiakiModels
import Foundation
import Testing

@Suite struct UserDataArgumentTests {
    @Test func withoutTheOptionEveryArgumentIsLeftForTheLaunchParser() throws {
        let option = try UserDataArgument(arguments: ["ChiakiNG", "--stream", "Den", "--zoom"])
        #expect(option.directory == nil)
        #expect(option.remaining == ["ChiakiNG", "--stream", "Den", "--zoom"])
    }

    @Test func theFolderFollowsTheOptionOrItsEqualsSign() throws {
        let spaced = try UserDataArgument(arguments: ["ChiakiNG", "--user-data", "/tmp/clone", "--list"])
        let joined = try UserDataArgument(arguments: ["ChiakiNG", "--list", "--user-data=/tmp/clone"])
        #expect(spaced.directory?.path == "/tmp/clone")
        #expect(joined.directory?.path == "/tmp/clone")
        #expect(spaced.remaining == ["ChiakiNG", "--list"])
        #expect(joined.remaining == ["ChiakiNG", "--list"])
    }

    @Test func aRelativeFolderIsResolvedAgainstTheCurrentDirectory() throws {
        let option = try UserDataArgument(arguments: ["ChiakiNG", "--user-data", "clone/../copy"])
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("copy").standardizedFileURL.path
        #expect(option.directory?.path == expected)
    }

    @Test func aMissingOrRepeatedFolderIsRefused() {
        #expect(throws: UserDataArgument.Failure.missingDirectory) {
            try UserDataArgument(arguments: ["ChiakiNG", "--user-data"])
        }
        #expect(throws: UserDataArgument.Failure.missingDirectory) {
            try UserDataArgument(arguments: ["ChiakiNG", "--user-data="])
        }
        #expect(throws: UserDataArgument.Failure.repeated) {
            try UserDataArgument(arguments: ["ChiakiNG", "--user-data", "/a", "--user-data=/b"])
        }
    }
}
