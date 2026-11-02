@testable import ChiakiFeatures
import ChiakiModels
import ChiakiClients
import ChiakiClientsLive
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiNG

private func legacy(
    keyboardEnabled: Bool,
    _ change: (inout ControlsConfiguration) -> Void = { _ in
    }
) throws -> ControlsConfiguration {
    var configuration = ControlsConfiguration()
    change(&configuration)
    var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration))
        as? [String: Any] ?? [:]
    saved.removeValue(forKey: "keyboardMode")
    saved["keyboardEnabled"] = keyboardEnabled
    saved["consoleTextEntry"] = true
    return try JSONDecoder().decode(
        ControlsConfiguration.self,
        from: JSONSerialization.data(withJSONObject: saved)
    )
}

@Test func keyboardTypesOnTheConsoleByDefault() {
    #expect(ControlsConfiguration().keyboardMode == .typeOnConsole)
}

@Test func savedKeyboardControlsKeepTheirModeOnlyWhenTheyWereCustomised() throws {
    #expect(try legacy(keyboardEnabled: true).keyboardMode == .typeOnConsole)
    #expect(try legacy(keyboardEnabled: false).keyboardMode == .typeOnConsole)
    let customised: (inout ControlsConfiguration) -> Void = { configuration in
        configuration.presets[0].bindings[0].code = 99
    }
    #expect(try legacy(keyboardEnabled: true, customised).keyboardMode == .controller)
    #expect(try legacy(keyboardEnabled: false, customised).keyboardMode == .typeOnConsole)
    let controllerCopy: (inout ControlsConfiguration) -> Void = { configuration in
        _ = configuration.givePreset(to: "pad", named: "Xbox Series X Controller", touchpad: false)
        configuration.presets[1].bindings.removeAll {
            $0.source == .macKey && $0.target == .touchpad
        }
    }
    #expect(try legacy(keyboardEnabled: true, controllerCopy).keyboardMode == .typeOnConsole)
    let keyboardOnly: (inout ControlsConfiguration) -> Void = { configuration in
        configuration.selectedControllerKey = ControlsConfiguration.keyboardOnlyKey
    }
    #expect(try legacy(keyboardEnabled: true, keyboardOnly).keyboardMode == .controller)
}

@Test func keyboardModeSurvivesSavingWithoutTheOldKeys() throws {
    var configuration = ControlsConfiguration()
    configuration.keyboardMode = .controller
    let data = try JSONEncoder().encode(configuration)
    let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    #expect(saved["keyboardEnabled"] == nil)
    #expect(saved["consoleTextEntry"] == nil)
    #expect(try JSONDecoder().decode(ControlsConfiguration.self, from: data) == configuration)
}

@MainActor @Test func consoleTextEntryIsOnlyForStreamsThatCannotTakeTyping() {
    #expect(ConsoleStreamLauncher.usesTextEntry(ps5: false))
    #if os(iOS)
        #expect(ConsoleStreamLauncher.usesTextEntry(ps5: true))
    #else
        #expect(!ConsoleStreamLauncher.usesTextEntry(ps5: true))
    #endif
}
