@testable import ChiakiFeatures
import ChiakiModels
@testable import ChiakiNG
import Foundation
import Testing

private let account = UUID()
private let other = UUID()
private let consoleID = UUID()
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, id: consoleID, name: "Living Room", hardwareID: "AABBCCDDEEFF"
)
private let registration = RegistrationFlow.Registration(profileID: account, console: console)

@Test func launchCommandLineSeparatesCommandsThatNeverOpenAWindow() {
    #expect(LaunchCommandLine.command(from: ["ChiakiNG"]) == .run(nil))
    #expect(LaunchCommandLine.command(from: ["ChiakiNG", "--list"]) == .list)
    #expect(LaunchCommandLine.command(from: ["ChiakiNG", "--stream", "Den"])
        == .run(.stream(LaunchStream(console: .name("Den")))))
    #expect(LaunchCommandLine.command(from: ["ChiakiNG", "--stream"])
        == .invalid(LaunchRequestError.missingConsole.message))
}

@MainActor @Test func launchListingPrintsEachConsoleOnce() {
    let shared = RegistrationFlow.Registration(profileID: other, console: console)
    let unnamed = RegistrationFlow.Registration(
        profileID: account,
        console: RegistrationFlow.ConsoleTarget(address: "192.0.2.9", kind: .ps4)
    )
    #expect(LaunchCommandLine.listing([registration, shared, unnamed]) == """
    Host: Living Room
        id: \(consoleID.uuidString)
        address: 192.0.2.5
    Host: 192.0.2.9
        address: 192.0.2.9
    """)
    #expect(LaunchCommandLine.listing([]) == "No registered consoles.")
}
