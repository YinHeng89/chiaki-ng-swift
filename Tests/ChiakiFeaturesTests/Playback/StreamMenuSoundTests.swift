@testable import ChiakiFeatures
import ChiakiModels
import ChiakiClients
import Foundation
import Testing
import ComposableArchitecture

@Test func soundRenderingPrefers3DOnHeadphonesAndSpatialElsewhere() {
    let both = SpatialAudio()
    #expect(both.rendering(for: .headphones) == .audio3D)
    #expect(both.rendering(for: .speakers) == .spatial)
    #expect(both.rendering(for: .headphones, audio3DAvailable: false) == .spatial)
    let spatialOnly = SpatialAudio(audio3D: false)
    #expect(spatialOnly.rendering(for: .headphones) == .spatial)
    #expect(spatialOnly.rendering(for: .speakers) == .spatial)
    let audio3DOnly = SpatialAudio(appleSpatial: false)
    #expect(audio3DOnly.rendering(for: .headphones) == .audio3D)
    #expect(audio3DOnly.rendering(for: .speakers) == .stereo)
    let neither = SpatialAudio(audio3D: false, appleSpatial: false)
    #expect(neither.rendering(for: .headphones) == .stereo)
    #expect(neither.rendering(for: .speakers) == .stereo)
}

@Test func streamMenuAudio3DIsOfferedWhereTheTuningCarriesIt() {
    func reason(_ context: StreamTuningContext, available: Bool) -> String? {
        var state = StreamMenuReducer.State(context: context)
        state.draft.audio3DAvailable = available
        return state.audio3DDisabledReason.map { String(localized: $0) }
    }
    #expect(reason(.cloud("pscloud"), available: true) == nil)
    #expect(reason(.console(.local, ps5: true), available: true) == nil)
    #expect(reason(.console(.remote, ps5: true), available: true) == nil)
    #expect(reason(.cloud("psnow"), available: false) == "Not supported on PS Now")
    #expect(reason(.console(.local, ps5: false), available: false) == "Not supported on PS4")
    #expect(reason(.guest, available: true) == "Not supported as a guest")
}

@MainActor @Test func streamMenuEditsChangeAudio3DAndSpatialIndependently() async {
    let id = UUID()
    let loaded = StreamTuningConfiguration(volume: 0.7, spatialAudio: SpatialAudio())
    let saved = LockIsolated<[StreamTuningConfiguration]>([])
    let store = TestStore(initialState: StreamMenuReducer.State(context: .cloud("pscloud"))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.streamSession.loadTuning = { _ in
            loaded
        }
        $0.streamSession.saveTuning = { _, value in
            saved.withValue {
                $0.append(value)
            }
        }
        $0.settings = .inMemory([ConsolePowerSettings()])
    }
    store.exhaustivity = .off
    await store.send(.load)
    await store.receive(\.loaded)
    var disable3D = store.state.draft
    disable3D.spatialAudio.audio3D = false
    await store.send(.edit(disable3D)) {
        $0.draft.spatialAudio = SpatialAudio(audio3D: false)
    }
    await store.send(.save)
    await store.receive(\.saved)
    var disableSpatial = store.state.draft
    disableSpatial.spatialAudio.appleSpatial = false
    await store.send(.edit(disableSpatial)) {
        $0.draft.spatialAudio = SpatialAudio(audio3D: false, appleSpatial: false)
    }
    await store.send(.save)
    await store.receive(\.saved)
    #expect(saved.value.map(\.spatialAudio) == [
        SpatialAudio(audio3D: false),
        SpatialAudio(audio3D: false, appleSpatial: false)
    ])
    #expect(saved.value.map(\.volume) == [0.7, 0.7])
}
