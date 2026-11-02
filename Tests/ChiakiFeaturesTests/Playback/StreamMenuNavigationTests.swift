@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Suite struct StreamMenuNavigationTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    private func loadedState(edited: Bool) -> StreamMenuReducer.State {
        var state = StreamMenuReducer.State(context: .guest)
        state.hasLoaded = true
        state.phase = .ready
        if edited {
            state.draft.volume = 0.25
        }
        return state
    }

    @Test func theMenuOpensOnItsLastPanelAndReturnsToGameplayOnTheSamePanel() async {
        let store = TestStore(initialState: loadedState(edited: false)) {
            StreamMenuReducer()
        }
        await store.send(.open) {
            $0.navigation = .panel(.picture)
        }
        await store.send(.open)
        await store.send(.selectPanel(.sound)) {
            $0.navigation = .panel(.sound)
        }
        await store.send(.returnToGameplay(save: true)) {
            $0.navigation = .gameplay(.sound)
        }
        await store.send(.returnToGameplay(save: true))
        await store.send(.open) {
            $0.navigation = .panel(.sound)
        }
    }

    @Test func leavingThePanelSavesItsChangesUnlessAskedNotTo() async {
        let store = TestStore(initialState: loadedState(edited: true)) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .constant(id)
        }
        store.exhaustivity = .off
        await store.send(.open)
        await store.send(.returnToGameplay(save: true)) {
            $0.navigation = .gameplay(.picture)
            $0.phase = .saving(id)
        }
        await store.receive(\.saved)

        let unsaved = TestStore(initialState: loadedState(edited: true)) {
            StreamMenuReducer()
        }
        await unsaved.send(.open) {
            $0.navigation = .panel(.picture)
        }
        await unsaved.send(.returnToGameplay(save: false)) {
            $0.navigation = .gameplay(.picture)
        }
        await unsaved.send(.disappeared)
    }

    @Test func choosingAPanelDuringGameplayIsTheOneTheMenuOpensOn() async {
        let store = TestStore(initialState: loadedState(edited: false)) {
            StreamMenuReducer()
        }
        await store.send(.selectPanel(.statistics)) {
            $0.navigation = .gameplay(.statistics)
        }
        await store.send(.open) {
            $0.navigation = .panel(.statistics)
        }
    }

    @Test func disappearingSavesOnlyWhileTheMenuHoldsNavigation() async {
        var initial = loadedState(edited: true)
        initial.navigation = .panel(.picture)
        let store = TestStore(initialState: initial) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .constant(id)
        }
        store.exhaustivity = .off
        await store.send(.disappeared) {
            $0.phase = .saving(id)
        }
        await store.receive(\.saved)
    }
}
