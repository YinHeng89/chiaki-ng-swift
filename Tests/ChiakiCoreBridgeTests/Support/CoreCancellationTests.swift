import enum ChiakiBridge.chiaki_bridge
@testable import ChiakiCoreBridge
import Foundation
import Testing

@Suite struct CoreCancellationTests {
    private static func waitForCancellation(of request: chiaki_bridge.Request) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 5)
        while !request.cancelled(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        return request.cancelled()
    }

    @Test func cancellingTheWaitingTaskCancelsTheRequestTheWorkHolds() async {
        let (started, starting) = AsyncStream<Void>.makeStream()
        let task = Task {
            await CoreCancellation.run { request in
                starting.yield()
                return Self.waitForCancellation(of: request)
            }
        }
        for await _ in started {
            break
        }
        task.cancel()
        #expect(await task.value)
    }

    @Test func workThatIsLeftAloneSeesNoCancellationAndReturnsItsValue() async {
        let value = await CoreCancellation.run { request in
            request.cancelled()
                ? -1
                : 42
        }
        #expect(value == 42)
    }

    @Test func aTaskCancelledBeforeTheWorkStartsHandsItACancelledRequest() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CoreCancellation.run { request in
                request.cancelled()
            }
        }
        #expect(await task.value)
    }
}
