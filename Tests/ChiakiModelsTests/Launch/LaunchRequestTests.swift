import ChiakiModels
import Foundation
import Testing

@Test func launchArgumentsWithoutCommandsOpenTheAppNormally() throws {
    #expect(try LaunchRequestParser.parse(arguments: []) == nil)
    #expect(try LaunchRequestParser.parse(arguments: ["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    #expect(try LaunchRequestParser.parse(arguments: ["--diagnose-playback"]) == nil)
}

@Test func launchArgumentsListConsoles() throws {
    #expect(try LaunchRequestParser.parse(arguments: ["--list"]) == .list)
    #expect(try LaunchRequestParser.parse(arguments: ["list"]) == .list)
}

@Test func launchArgumentsStreamByNameWithDisplayAndExit() throws {
    let request = try LaunchRequestParser.parse(arguments: [
        "--stream", "Living Room", "--zoom", "--exit-app-on-stream-exit"
    ])
    #expect(request == .stream(LaunchStream(
        console: .name("Living Room"),
        display: .fullscreen(.zoom),
        exit: .quitApp
    )))
    #expect(try LaunchRequestParser.parse(arguments: ["--stream=Den", "--stretch"])
        == .stream(LaunchStream(console: .name("Den"), display: .fullscreen(.stretch))))
    #expect(try LaunchRequestParser.parse(arguments: ["--fullscreen", "--stream", "Den", "--remote"])
        == .stream(LaunchStream(console: .name("Den"), route: .remote, display: .fullscreen(.fit))))
}

@Test func launchArgumentsAcceptTheUpstreamPositionalForm() throws {
    #expect(try LaunchRequestParser.parse(arguments: ["stream", "PS5-123", "192.168.1.20", "--fullscreen"])
        == .stream(LaunchStream(console: .name("PS5-123"), display: .fullscreen(.fit))))
}

@Test func launchArgumentsReadConsoleIdentifiers() throws {
    let id = UUID()
    #expect(try LaunchRequestParser.parse(arguments: ["--stream", id.uuidString])
        == .stream(LaunchStream(console: .id(id))))
}

@Test func launchArgumentsKeepTheExitFlagWithoutAStream() throws {
    #expect(try LaunchRequestParser.parse(arguments: ["--exit-app-on-stream-exit"]) == .session(.quitApp))
}

@Test func launchArgumentsRejectInvalidCombinations() {
    #expect(throws: LaunchRequestError.missingConsole) {
        try LaunchRequestParser.parse(arguments: ["--stream"])
    }
    #expect(throws: LaunchRequestError.missingConsole) {
        try LaunchRequestParser.parse(arguments: ["--stream", "--zoom"])
    }
    #expect(throws: LaunchRequestError.missingConsole) {
        try LaunchRequestParser.parse(arguments: ["stream"])
    }
    #expect(throws: LaunchRequestError.conflictingDisplayModes) {
        try LaunchRequestParser.parse(arguments: ["--stream", "Den", "--zoom", "--stretch"])
    }
    #expect(throws: LaunchRequestError.conflictingCommands) {
        try LaunchRequestParser.parse(arguments: ["--list", "--stream", "Den"])
    }
    #expect(throws: LaunchRequestError.streamOptionWithoutStream("--fullscreen")) {
        try LaunchRequestParser.parse(arguments: ["--fullscreen"])
    }
    #expect(throws: LaunchRequestError.streamOptionWithoutStream("--remote")) {
        try LaunchRequestParser.parse(arguments: ["--remote"])
    }
}

@Test func launchURLsStreamAConsoleWithModeAndExit() throws {
    let id = UUID()
    let url = try #require(URL(string: "chiaki-ng://stream/\(id.uuidString)?mode=fullscreen&exit=1"))
    #expect(try LaunchRequestParser.parse(url: url) == .stream(LaunchStream(
        console: .id(id),
        display: .fullscreen(.fit),
        exit: .quitApp
    )))
    let named =
        try #require(URL(string: "CHIAKI-NG://Stream/Living%20Room?mode=stretch&route=remote&exit=false"))
    #expect(try LaunchRequestParser.parse(url: named) == .stream(LaunchStream(
        console: .name("Living Room"),
        route: .remote,
        display: .fullscreen(.stretch)
    )))
    let percent = try #require(URL(string: "chiaki-ng://stream/100%25%20Fun"))
    #expect(try LaunchRequestParser.parse(url: percent) == .stream(LaunchStream(console: .name("100% Fun"))))
    let slash = try #require(URL(string: "chiaki-ng://stream/A%2FB"))
    #expect(try LaunchRequestParser.parse(url: slash) == .stream(LaunchStream(console: .name("A/B"))))
    let plain = try #require(URL(string: "chiaki-ng://stream/Den?unknown=1"))
    #expect(try LaunchRequestParser.parse(url: plain) == .stream(LaunchStream(console: .name("Den"))))
}

@Test func launchURLsRejectMalformedRequests() throws {
    let other = try #require(URL(string: "https://stream/Den"))
    #expect(throws: LaunchRequestError.unsupportedURL("https://stream/Den")) {
        try LaunchRequestParser.parse(url: other)
    }
    let action = try #require(URL(string: "chiaki-ng://settings/Den"))
    #expect(throws: LaunchRequestError.unsupportedURL("chiaki-ng://settings/Den")) {
        try LaunchRequestParser.parse(url: action)
    }
    let missing = try #require(URL(string: "chiaki-ng://stream/"))
    #expect(throws: LaunchRequestError.missingConsole) {
        try LaunchRequestParser.parse(url: missing)
    }
    let mode = try #require(URL(string: "chiaki-ng://stream/Den?mode=huge"))
    #expect(throws: LaunchRequestError.unknownMode("huge")) {
        try LaunchRequestParser.parse(url: mode)
    }
    let exit = try #require(URL(string: "chiaki-ng://stream/Den?exit=maybe"))
    #expect(throws: LaunchRequestError.unknownExitValue("maybe")) {
        try LaunchRequestParser.parse(url: exit)
    }
    let route = try #require(URL(string: "chiaki-ng://stream/Den?route=cloud"))
    #expect(throws: LaunchRequestError.unknownRoute("cloud")) {
        try LaunchRequestParser.parse(url: route)
    }
}

@Test func launchDisplayMapsToVideoFit() {
    #expect(LaunchDisplay.window.videoFit == nil)
    #expect(LaunchDisplay.fullscreen(.fit).videoFit == VideoFit(mode: .fit))
    #expect(LaunchDisplay.fullscreen(.zoom).videoFit == VideoFit(mode: .zoom))
    #expect(LaunchDisplay.fullscreen(.stretch).videoFit == VideoFit(mode: .stretch))
}
