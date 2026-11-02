import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private func configuration(_ rgb: UInt32) -> ControlsConfiguration {
    var configuration = ControlsConfiguration()
    configuration.lightbar = .fixed(rgb: rgb)
    return configuration
}

private func ready(saved: UInt32, draft: UInt32) -> ControlsSettingsFeature.State {
    var controls = ControlsSettingsFeature.State.loaded(configuration(saved))
    controls.draft = configuration(draft)
    return controls
}

@Test func controllerLightsShowTheSavedColoursWhenNothingIsBeingEdited() {
    var state = RootFeature.State()
    state.settings.controls = ready(saved: 0x0000ff, draft: 0xff0000)
    #expect(RootControllerLights.wanted(in: state) == configuration(0x0000ff).lightbars)
}

@Test func controllerLightsPreviewTheSettingsDraftOnlyOnTheControlsTab() {
    var state = RootFeature.State()
    state.settings.controls = ready(saved: 0x0000ff, draft: 0xff0000)
    state.destination = .settings
    state.settings.route = .controls
    #expect(RootControllerLights.wanted(in: state) == configuration(0xff0000).lightbars)
    state.settings.route = .picture
    #expect(RootControllerLights.wanted(in: state) == configuration(0x0000ff).lightbars)
}

@Test func controllerLightsKeepTheDraftWhileItIsBeingSaved() {
    var state = RootFeature.State()
    state.settings.controls = ready(saved: 0x0000ff, draft: 0xff0000)
    state.settings.controls.setting = .saving(
        OperationID(),
        saved: configuration(0x0000ff),
        draft: configuration(0xff0000)
    )
    #expect(RootControllerLights.wanted(in: state) == configuration(0xff0000).lightbars)
}

@Test func controllerLightsPreferTheInStreamControlsDraft() {
    var state = RootFeature.State()
    state.settings.controls = ready(saved: 0x0000ff, draft: 0xff0000)
    state.destination = .settings
    state.settings.route = .controls
    state.stream.couch.overlay = .controls(CouchControlsFeature.State(
        pad: 0,
        settings: ready(saved: 0x0000ff, draft: 0x00ff00)
    ))
    #expect(RootControllerLights.wanted(in: state) == configuration(0x00ff00).lightbars)
    state.stream.couch.overlay = .controls(CouchControlsFeature.State(
        pad: 0,
        settings: ready(saved: 0x0000ff, draft: 0xffffff)
    ))
    #expect(RootControllerLights.wanted(in: state) == configuration(0xffffff).lightbars)
}

@Test func adoptingAnInStreamSaveNeverOverwritesAPendingSettingsEdit() {
    var clean = ready(saved: 0x0000ff, draft: 0x0000ff)
    clean.adopt(configuration(0x00ff00))
    #expect(clean.configuration == configuration(0x00ff00))
    #expect(clean.draft == configuration(0x00ff00))
    var capturing = ready(saved: 0x0000ff, draft: 0xff0000)
    capturing.mode = .capturing(ControlsCapture(id: UUID(), target: .cross))
    capturing.adopt(configuration(0x00ff00))
    #expect(capturing.configuration == configuration(0x0000ff))
    #expect(capturing.draft == configuration(0xff0000))
    var saving = ready(saved: 0x0000ff, draft: 0xff0000)
    saving.setting = .saving(OperationID(), saved: configuration(0x0000ff), draft: configuration(0xff0000))
    saving.adopt(configuration(0x00ff00))
    #expect(saving.configuration == configuration(0x0000ff))
}

@MainActor @Test func controllerLightsAreShownOnlyWhenTheyChange() async {
    let shown = LockIsolated<[ControllerLightbars]>([])
    var initial = RootFeature.State()
    initial.settings.controls = ready(saved: 0x0000ff, draft: 0x0000ff)
    initial.destination = .settings
    initial.settings.route = .controls
    let store = TestStore(initialState: initial) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.controllers.showLights = { lightbars in
            shown.withValue { $0.append(lightbars) }
        }
    }
    store.exhaustivity = .off
    await store.send(.settings(.controls(.edit(configuration(0xff0000)))))
    await store.send(.settings(.controls(.edit(configuration(0xff0000)))))
    await store.finish()
    #expect(shown.value == [configuration(0xff0000).lightbars])
}
