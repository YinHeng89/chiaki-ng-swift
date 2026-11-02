import ChiakiModels
import Foundation
import Testing

private func pad(_ key: String) -> ControllerDevice {
    ControllerDevice(
        id: 7, preferenceKey: key, name: "DualSense", transport: "USB", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    )
}

@Test func lightbarFollowsTheGameUntilAnOverrideIsSaved() {
    let lightbars = ControlsConfiguration().lightbars
    #expect(lightbars.color(for: pad("unit:a"), game: 0x123456) == 0x123456)
    #expect(lightbars.color(for: pad("unit:a"), game: nil) == nil)
}

@Test func controllerOverrideWinsOverTheGlobalFallback() {
    var configuration = ControlsConfiguration()
    configuration.lightbar = .fixed(rgb: 0xff0000)
    var followsGame = ControllerPreferences()
    followsGame.lightbar = .followGame
    var green = ControllerPreferences()
    green.lightbar = .fixed(rgb: 0x00ff00)
    configuration.controllers["unit:follow"] = followsGame
    configuration.controllers["unit:green"] = green
    configuration.controllers["unit:default"] = ControllerPreferences()
    let lightbars = configuration.lightbars
    #expect(lightbars.color(for: pad("unit:default"), game: 0x0000ff) == 0xff0000)
    #expect(lightbars.color(for: pad("unit:unknown"), game: nil) == 0xff0000)
    #expect(lightbars.color(for: pad("unit:follow"), game: 0x0000ff) == 0x0000ff)
    #expect(lightbars.color(for: pad("unit:green"), game: 0x0000ff) == 0x00ff00)
    #expect(lightbars.color(for: .keyboard, game: 0x0000ff) == 0x0000ff)
    #expect(lightbars.color(for: nil, game: 0x0000ff) == 0x0000ff)
}

@Test func lightbarRejectsColoursOutsideTwentyFourBits() throws {
    var configuration = ControlsConfiguration()
    configuration.lightbar = .fixed(rgb: 0xffffff)
    #expect(throws: Never.self) {
        try configuration.validated()
    }
    var preferences = ControllerPreferences()
    preferences.lightbar = .fixed(rgb: 0x1000000)
    configuration.controllers["unit:bad"] = preferences
    #expect(throws: InputFailure.invalidConfiguration) {
        try configuration.validated()
    }
}

@Test func internetConnectionSettingsDefaultToAutomaticGuessing() throws {
    let decoded = try JSONDecoder().decode(InternetConnectionSettings.self, from: Data("{}".utf8))
    #expect(decoded == InternetConnectionSettings())
    #expect(!decoded.forcePortGuessing)
    #expect(decoded.portGuessCount == InternetConnectionSettings.defaultPortGuessCount)
    #expect(throws: InternetConnectionSettingsFailure.invalidPortGuessCount) {
        try InternetConnectionSettings(portGuessCount: 4).validated()
    }
}

@Test func lightLedgerSendsOnlyChangesAndReleasesSeatsThatLeave() {
    let host = pad("unit:host")
    let guest = ControllerDevice(
        id: 9, preferenceKey: "unit:guest", name: "DualShock 4", transport: "USB", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    )
    let xbox = ControllerDevice(
        id: 11, preferenceKey: "unit:xbox", name: "Xbox", transport: "USB", individual: true,
        rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
    )
    var plan = ControllerLightPlan(devices: [0: host, 1: guest, 2: xbox])
    var ledger = ControllerLightLedger()
    var changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors.isEmpty)
    #expect(changes.players == [7: 0, 9: 1, 11: 2])
    plan.gameColors = [0: 0x0000ff, 1: 0xff0000, 2: 0x00ff00]
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors == [7: 0x0000ff, 9: 0xff0000])
    #expect(changes.players.isEmpty)
    #expect(ledger.reconcile(to: plan.targets()).isEmpty)
    plan.lightbars = ControllerLightbars(controllers: ["unit:guest": .fixed(rgb: 0xffffff)])
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors == [9: 0xffffff])
    #expect(plan.playerOneColor == 0x0000ff)
    plan.devices[1] = nil
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.released == [9: true])
    #expect(changes.colors.isEmpty)
    plan.devices[1] = guest
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors == [9: 0xffffff])
    #expect(changes.players == [9: 1])
    plan.lightbars = ControllerLightbars()
    plan.gameColors[1] = nil
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors.isEmpty)
    #expect(changes.defaults == [9])
    #expect(ledger.reconcile(to: plan.targets()).isEmpty)
    plan.gameColors[1] = 0x000000
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.colors == [9: 0x000000])
    plan.devices = [:]
    changes = ledger.reconcile(to: plan.targets())
    #expect(changes.released == [7: true, 9: true, 11: false])
    #expect(changes.colors.isEmpty)
    #expect(changes.defaults.isEmpty)
}

@Test func controllersWithoutALightBarShowTheGameColour() {
    let xbox = ControllerDevice(
        id: 11, preferenceKey: "unit:xbox", name: "Xbox", transport: "USB", individual: true,
        rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
    )
    let lightbars = ControllerLightbars(
        global: .fixed(rgb: 0xff0000),
        controllers: ["unit:xbox": .fixed(rgb: 0x00ff00)]
    )
    #expect(lightbars.color(for: xbox, game: 0x0000ff) == 0x0000ff)
    #expect(ControllerLightPlan(lightbars: lightbars, gameColors: [0: 0x0000ff], devices: [0: xbox])
        .playerOneColor == 0x0000ff)
}
