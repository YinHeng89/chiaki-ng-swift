@testable import ChiakiModels
import Foundation
import Testing

private let ownedByTheUser: [String] = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["Library/Application Support", "Library/Logs", "Library/Caches", "Library/Preferences"].map {
        "\(home)/\($0)"
    }
}()

private func reachesTheUser(_ path: String) -> Bool {
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    return ownedByTheUser.contains { resolved.hasPrefix($0) }
}

@Test func aTestProcessIsRecognisedAsAHarness() {
    #expect(HostProcess.current.isHarness)
}

@Test func aTestProcessCannotBuildTheLiveUserDataLocation() {
    #expect(throws: UserData.Refusal.harnessProcess) {
        try UserData.live()
    }
}

@Test func aTestProcessResolvesNoPathUnderTheUsersLibrary() {
    let data = UserData.current
    #expect(data.keys == .memory)
    for url in [data.support, data.logs, data.caches, data.database, data.catalog] {
        #expect(!reachesTheUser(url.path))
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
    #expect(!reachesTheUser(LogSettings.defaults.directory))
    #expect(LogSettings.defaults.directory == data.logs.path)
    #expect(UserData.current == data)
}

@Test func everyScratchLocationIsItsOwnDirectory() {
    let first = UserData.scratch()
    let second = UserData.scratch()
    #expect(first.support != second.support)
    #expect(first.keys == .memory)
    #expect(!reachesTheUser(first.support.path))
}

@Test func anyOneHarnessSignalKeepsAProcessOffUserData() {
    func process(
        environment: [String: String] = [:], name: String = "ChiakiNG", bundles: [String] = [],
        hasTestRuntime: Bool = false
    ) -> HostProcess {
        HostProcess(environment: environment, name: name, bundles: bundles, hasTestRuntime: hasTestRuntime)
    }
    #expect(!process().isHarness)
    #expect(!process(environment: ["CHIAKI_HEADLESS_TESTS": "0"], bundles: ["/Applications/Chiaki.app"])
        .isHarness)
    #expect(process(environment: ["CHIAKI_HEADLESS_TESTS": "1"]).isHarness)
    #expect(process(environment: ["XCTestConfigurationFilePath": ""]).isHarness)
    #expect(process(environment: ["XCTestBundlePath": "/x"]).isHarness)
    #expect(process(environment: ["XCTestSessionIdentifier": "1"]).isHarness)
    #expect(process(environment: ["SWIFT_TESTING_ENABLED": "1"]).isHarness)
    #expect(process(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]).isHarness)
    #expect(process(name: "xctest").isHarness)
    #expect(process(name: "swiftpm-testing-helper").isHarness)
    #expect(process(bundles: ["/build/ChiakiNGPackageTests.xctest"]).isHarness)
    #expect(process(hasTestRuntime: true).isHarness)
    #expect(throws: UserData.Refusal.harnessProcess) {
        try UserData.live(in: process(hasTestRuntime: true))
    }
}

@Test func onlyTheUserDataLocationNamesTheUsersLibraryOrKeychain() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = root.appendingPathComponent("Sources")
    let allowed = [
        "applicationSupportDirectory": ["Sources/ChiakiModels/App/UserData.swift"],
        "cachesDirectory": ["Sources/ChiakiModels/App/UserData.swift"],
        "homeDirectoryForCurrentUser": ["Sources/ChiakiModels/App/UserData.swift"],
        "NSHomeDirectory": [],
        "Library/Logs": ["Sources/ChiakiModels/App/UserData.swift"],
        "Library/Application Support": [],
        "SecItem": ["Sources/ChiakiPersistence/Secrets/KeySource.swift"],
        "KeychainClient.live": [],
        "keys: .live": [],
        "UserData.install": ["Sources/ChiakiNG/Launch/LaunchCommandLine.swift"]
    ]
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offences: [String] = []
    var scanned = 0
    for case let file as URL in files
        where ["swift", "m", "mm", "cpp", "hpp", "h"].contains(file.pathExtension) {
        let text = try String(contentsOf: file, encoding: .utf8)
        let relative = String(file.path.dropFirst(root.path.count + 1))
        scanned += 1
        for (token, homes) in allowed where text.contains(token) && !homes.contains(relative) {
            offences.append("\(relative): \(token)")
        }
    }
    #expect(scanned > 100)
    #expect(offences.sorted() == [])
}
