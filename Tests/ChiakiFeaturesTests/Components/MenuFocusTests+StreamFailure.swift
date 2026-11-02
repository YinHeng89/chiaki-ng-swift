import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

private enum FailureChoice: Equatable {
    case stop
    case retry
    case exit
}

extension MenuFocusTests {
    @MainActor
    private func failedCloudStream(_ failure: StreamFailure) async -> StreamFeature.State {
        let session = StreamSessionID(uuid: UUID(0))
        let calls = StreamSessionCalls()
        let store = calls.store()
        await store.send(.start(.cloud(CloudStreamRequest(
            profile: ProfileID(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!),
            title: CloudStreamTitle(
                product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
                name: "Example",
                service: .psCloud
            )
        ))))
        await store.send(.event(session, .firstFrame))
        await store.send(.failed(session, failure))
        let state = store.state
        await store.send(.stop)
        await store.skipReceivedActions()
        return state
    }

    private func failureHarness(
        _ state: StreamFeature.State,
        actions: LockIsolated<[FailureChoice]>
    ) -> MenuFocusHarness {
        let store: StoreOf<StreamFeature> = Store(initialState: state) {
            Reduce<StreamFeature.State, StreamFeature.Action> { _, action in
                switch action {
                case .stop:
                    actions.withValue {
                        $0.append(.stop)
                    }
                case .retry:
                    actions.withValue {
                        $0.append(.retry)
                    }
                case .view(.requestExit):
                    actions.withValue {
                        $0.append(.exit)
                    }
                default:
                    break
                }
                return .none
            }
        }
        return MenuFocusHarness(width: 1000, height: 760) { _ in
            MenuFocusHostingView(rootView: StreamView(store: store) {
                EmptyView()
            })
        }
    }

    @Test func aFailedCloudStreamStartsOnTryAgainAndMovesToBackToLibrary() async {
        let state = await failedCloudStream(.stream(.consoleQuit(.consoleDisconnected), overInternet: true))
        #expect(state.status == .failed)
        #expect(state.offersRetry)
        let actions = LockIsolated<[FailureChoice]>([])
        let harness = failureHarness(state, actions: actions)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(actions.value.last == .retry)
        await harness.send([.left, .confirm])
        await harness.pause(150)
        #expect(actions.value.last == .stop)
        await harness.send([.right, .confirm])
        await harness.pause(150)
        #expect(actions.value.last == .retry)
        await harness.send(.back)
        await harness.pause(150)
        #expect(actions.value.last == .exit)
    }

    @Test func anEndedTrialStartsOnBackToLibraryWithNoTryAgain() async {
        let state = await failedCloudStream(.stream(.consoleQuit(.trialEnded), overInternet: true))
        #expect(state.status == .failed)
        #expect(!state.offersRetry)
        let actions = LockIsolated<[FailureChoice]>([])
        let harness = failureHarness(state, actions: actions)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(actions.value == [.stop])
        await harness.send([.right, .confirm, .left, .confirm])
        await harness.pause(150)
        #expect(actions.value == [.stop, .stop, .stop])
        await harness.send(.back)
        await harness.pause(150)
        #expect(actions.value.last == .exit)
    }
}
