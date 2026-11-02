import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct LifecycleFeatureTests {
    let id = OperationID(uuid: UUID(0))

    @Test func quittingStopsEverythingOnceAndOnlyItsShutdownCompletesIt() async {
        let clock = TestClock()
        let store = TestStore(initialState: LifecycleFeature.State()) {
            LifecycleFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.platform.shutdown = {
                try? await clock.sleep(for: .seconds(1))
            }
        }
        await store.send(.terminationRequested) {
            $0.termination = .stopping(id)
        }
        await store.receive(.delegate(.terminating))
        await store.send(.terminationRequested)
        await store.send(.terminationCompleted(OperationID(uuid: UUID(5))))
        await clock.advance(by: .seconds(1))
        await store.receive(.terminationCompleted(id)) {
            $0.termination = .ready
        }
    }

    @Test func sleepRestsTheConsoleOnlyForAConsoleStreamAndAlwaysLetsTheMacSleep() async {
        let events = LockIsolated<[String]>([])
        let store = TestStore(initialState: LifecycleFeature.State()) {
            LifecycleFeature()
        } withDependencies: {
            $0.platform = PlatformClient(
                shutdown: {},
                sleep: { rest in
                    events.withValue {
                        $0.append("sleep \(rest)")
                    }
                    return rest
                },
                restsConsoleOnSleep: {
                    true
                },
                allowSleep: { notification in
                    events.withValue {
                        $0.append("allow \(notification)")
                    }
                }
            )
        }
        let stream = StreamSessionID()
        await store.send(.systemWillSleep(1, consoleStreaming: true, stream: stream, guestJoin: nil))
        await store.receive(.delegate(.sleeping))
        await store.receive(.sleepStoppedStream(stream, guestJoin: nil))
        await store.receive(.delegate(.sleepStoppedStream(stream, guestJoin: nil)))
        await store.send(.systemWillSleep(2, consoleStreaming: false, stream: nil, guestJoin: nil))
        await store.receive(.delegate(.sleeping))
        await store.finish()
        #expect(events.value == ["sleep true", "allow 1", "sleep false", "allow 2"])
    }

    @Test func onceQuittingSleepAndWakeTouchNothing() async {
        let allowed = LockIsolated<[Int]>([])
        let store = TestStore(initialState: LifecycleFeature.State(termination: .ready)) {
            LifecycleFeature()
        } withDependencies: {
            $0.platform = PlatformClient(
                shutdown: {},
                sleep: { _ in
                    Issue.record("sleep after quitting")
                    return false
                },
                allowSleep: { notification in
                    allowed.withValue {
                        $0.append(notification)
                    }
                },
                woke: {
                    Issue.record("wake after quitting")
                }
            )
        }
        await store.send(.systemWillSleep(
            3,
            consoleStreaming: true,
            stream: StreamSessionID(),
            guestJoin: nil
        ))
        await store.send(.systemDidWake)
        await store.finish()
        #expect(allowed.value == [3])
    }
}
