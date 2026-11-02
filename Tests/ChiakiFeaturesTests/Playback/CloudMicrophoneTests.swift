import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let firstSession = StreamSessionID(uuid: UUID(0))

private func cloudSource(_ service: CloudService) -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
            name: "Example",
            service: service
        )
    ))
}

@MainActor @Test func aPS5CloudStreamOffersTheMicrophoneOnceItPlays() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource(.psCloud)))
    #expect(store.state.offersMicrophone)
    #expect(!store.state.microphone.available)
    await store.send(.event(firstSession, .firstFrame))
    #expect(store.state.microphone.available)
    await store.send(.stop)
    await store.skipReceivedActions()
    #expect(!store.state.microphone.available)
}

@MainActor @Test func aPSNowStreamOffersTheMicrophoneOnceItPlays() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource(.psNow)))
    #expect(store.state.offersMicrophone)
    #expect(!store.state.microphone.available)
    await store.send(.event(firstSession, .firstFrame))
    #expect(store.state.microphone.available)
    await store.send(.stop)
    await store.skipReceivedActions()
}
