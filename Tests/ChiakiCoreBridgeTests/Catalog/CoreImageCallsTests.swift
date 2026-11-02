import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import Foundation
import Testing

private actor Gate {
    private var inside = 0
    private var most = 0
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var ran: [Int] = []

    var peak: Int {
        most
    }

    var order: [Int] {
        ran
    }

    var current: Int {
        inside
    }

    func pass(_ number: Int) async {
        inside += 1
        most = max(most, inside)
        ran.append(number)
        if !open {
            await withCheckedContinuation { continuation in
                waiting.append(continuation)
            }
        }
        inside -= 1
    }

    func release() {
        open = true
        let held = waiting
        waiting = []
        for continuation in held {
            continuation.resume()
        }
    }
}

private func until(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@Test func coreImageCallsNeverRunMoreThanTheirLimit() async {
    let calls = CoreImageCalls(limit: 3)
    let gate = Gate()
    await withTaskGroup(of: Void.self) { group in
        for number in 0..<50 {
            group.addTask {
                _ = try? await calls.run {
                    await gate.pass(number)
                }
            }
        }
        #expect(await until { await calls.queued == 47 })
        #expect(await gate.current == 3)
        await gate.release()
    }
    #expect(await gate.peak == 3)
    #expect(await gate.order.count == 50)
    #expect(await calls.inFlight == 0)
    #expect(await calls.queued == 0)
}

@Test func aCancelledImageCallLeavesTheQueueWithoutRunning() async {
    let calls = CoreImageCalls(limit: 1)
    let gate = Gate()
    let first = Task {
        try await calls.run {
            await gate.pass(0)
        }
    }
    #expect(await until { await calls.inFlight == 1 })
    let scrolled = Task {
        try await calls.run {
            await gate.pass(1)
        }
    }
    let kept = Task {
        try await calls.run {
            await gate.pass(2)
        }
    }
    #expect(await until { await calls.queued == 2 })
    scrolled.cancel()
    #expect(await until { await calls.queued == 1 })
    await #expect(throws: CancellationError.self) {
        try await scrolled.value
    }
    await gate.release()
    _ = try? await first.value
    _ = try? await kept.value
    #expect(await gate.order == [0, 2])
    #expect(await calls.inFlight == 0)
}
