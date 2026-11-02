@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Records what a stream test's ``StreamSessionClient`` was asked to do.
final class StreamSessionCalls: Sendable {
    /// The sessions started.
    let started = LockIsolated<[StreamSessionID]>([])
    /// The sessions left.
    let left = LockIsolated<[StreamSessionID]>([])

    /// How each session was left.
    let exits = LockIsolated<[StreamExitAction]>([])

    /// How many home screen requests were sent.
    let homes = LockIsolated(0)
    /// The codes submitted.
    let codes = LockIsolated<[StreamAccessCode]>([])
    /// The datacenters chosen.
    let datacenters = LockIsolated<[String]>([])
    /// The keyboard commands sent.
    let keyboard = LockIsolated<[ConsoleKeyboardCommand]>([])

    /// A client whose sessions run until stopped, or fail at once with `failure`, keeping the other
    /// operations of `base`.
    ///
    /// - Parameters:
    ///   - failure: The failure every start ends with, if any.
    ///   - outcome: What leaving reports.
    ///   - base: The client whose other operations are kept.
    /// - Returns: The client.
    func client(
        failure: StreamFailure? = nil,
        outcome: StreamExitOutcome = .left,
        on base: StreamSessionClient = .testValue
    ) -> StreamSessionClient {
        var client = base
        client.start = { [started] id, _ in
            started.withValue {
                $0.append(id)
            }
            return AsyncThrowingStream { continuation in
                if let failure {
                    continuation.finish(throwing: failure)
                }
            }
        }
        client.submitAccessCode = { [codes] _, _, code in
            codes.withValue {
                $0.append(code)
            }
            return true
        }
        client.keyboard = { [keyboard] _, command in
            keyboard.withValue {
                $0.append(command)
            }
            return true
        }
        client.goHome = { [homes] _ in
            homes.withValue {
                $0 += 1
            }
            return true
        }
        client.selectDatacenter = { [datacenters] _, name in
            datacenters.withValue {
                $0.append(name)
            }
            return true
        }
        client.tune = { _, _ in
        }
        client.leave = { [left, exits] id, exit in
            left.withValue {
                $0.append(id)
            }
            exits.withValue {
                $0.append(exit)
            }
            return outcome
        }
        return client
    }

    /// A non-exhaustive store over a new stream with this client.
    ///
    /// - Parameters:
    ///   - failure: The failure every start ends with, if any.
    ///   - outcome: What leaving reports.
    ///   - clock: The test clock.
    ///   - initial: The starting state.
    ///   - dependencies: Further overrides.
    /// - Returns: The store.
    @MainActor func store(
        failure: StreamFailure? = nil,
        outcome: StreamExitOutcome = .left,
        clock: TestClock<Duration> = TestClock(),
        initial: StreamFeature.State = StreamFeature.State(),
        dependencies: @escaping (inout DependencyValues) -> Void = { _ in
        }
    ) -> TestStoreOf<StreamFeature> {
        let store = TestStore(initialState: initial) {
            StreamFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = clock
            $0.streamSession = self.client(failure: failure, outcome: outcome, on: $0.streamSession)
            $0.idleKakusanHosting()
            dependencies(&$0)
        }
        store.exhaustivity = .off
        return store
    }
}
