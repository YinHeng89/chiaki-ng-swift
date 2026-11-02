@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation

let hostSession = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!

struct KakusanHostEntry {
    let id: UUID
    let guest: UInt8
    let stage: KakusanHostStage

    init(_ id: UUID, _ guest: UInt8, _ stage: KakusanHostStage) {
        self.id = id
        self.guest = guest
        self.stage = stage
    }
}

func hostState(_ entries: [KakusanHostEntry], presented: UUID? = nil) -> KakusanHostFeature.State {
    var state = KakusanHostFeature.State()
    state.guests = IdentifiedArray(uniqueElements: entries.map { entry in
        KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
            entry.id,
            guest: entry.guest,
            through: entry.stage
        ))
    })
    state.destination = presented.map { .invite(KakusanInviteFeature.State(guest: $0)) }
    return state
}

func armed(_ state: KakusanHostFeature.State) -> KakusanHostFeature.State {
    var armed = state
    armed.followPresented()
    return armed
}
