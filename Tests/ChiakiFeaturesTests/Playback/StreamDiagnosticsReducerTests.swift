import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private func sample(_ step: Int, lost: Int = 0) -> StreamStatisticsSample {
    StreamStatisticsSample(
        statistics: RenderStatistics(fixture: [
            "surfaces": NSNumber(value: step * 30),
            "completed": NSNumber(value: step * 30),
            "bytes": NSNumber(value: step * 625_000),
            "lost": NSNumber(value: lost),
            "rttPresent": true,
            "rttSmoothedMicroseconds": 9000
        ]),
        uptime: Double(step) / 2
    )
}

@MainActor @Test func diagnosticsSampleTheStreamAndRestoreTheSavedAppearance() async {
    let saved = StreamDiagnosticsAppearance(level: .standard, glass: .clear)
    let (stream, continuation) = AsyncStream<StreamStatisticsSample>.makeStream()
    let store = TestStore(initialState: StreamDiagnosticsReducer.State()) {
        StreamDiagnosticsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.loadDiagnosticsAppearance = {
            saved
        }
        $0.streamSession.statisticsSamples = {
            stream
        }
    }
    store.exhaustivity = .off
    let task = await store.send(.task)
    await store.receive(\.appearanceLoaded) {
        $0.appearance = saved
        $0.preferences = .loaded
    }
    continuation.yield(sample(1))
    await store.receive(\.sampled)
    continuation.yield(sample(2))
    await store.receive(\.sampled)
    #expect(store.state.telemetry.sourceFPS == 60)
    #expect(store.state.telemetry.bitrateMbps == 10)
    #expect(store.state.history.frames.count == 1)
    await task.cancel()
}

@MainActor @Test func diagnosticsIgnoreSamplesFromAnEarlierRun() async {
    var state = StreamDiagnosticsReducer.State()
    state.sampling = .running(UUID(1))
    let store = TestStore(initialState: state) {
        StreamDiagnosticsReducer()
    }
    await store.send(.sampled(UUID(0), sample(1)))
}

@MainActor @Test func diagnosticsChoiceMadeWhileLoadingWinsAndIsSaved() async {
    var state = StreamDiagnosticsReducer.State()
    state.preferences = .loading(UUID(0))
    let saves = LockIsolated<[StreamDiagnosticsAppearance]>([])
    let store = TestStore(initialState: state) {
        StreamDiagnosticsReducer()
    } withDependencies: {
        $0.streamSession.saveDiagnosticsAppearance = { appearance in
            saves.withValue {
                $0.append(appearance)
            }
        }
    }
    await store.send(.selectLevel(.full)) {
        $0.appearance.level = .full
        $0.preferences = .loaded
    }
    await store.send(.appearanceLoaded(UUID(0), StreamDiagnosticsAppearance(level: .compact)))
    await store.send(.selectGlass(.solid)) {
        $0.appearance.glass = .solid
    }
    await store.send(.selectLayout(.floating)) {
        $0.appearance.layout = .floating
    }
    await store.finish()
    #expect(saves.value.last == StreamDiagnosticsAppearance(level: .full, glass: .solid, layout: .floating))
}

@MainActor @Test func diagnosticsCycleThroughEveryLevelAndGlass() async {
    let store = TestStore(initialState: StreamDiagnosticsReducer.State()) {
        StreamDiagnosticsReducer()
    }
    store.exhaustivity = .off
    var levels = [StreamDiagnosticsAppearance.Level]()
    for _ in 0..<4 {
        await store.send(.cycleLevel)
        levels.append(store.state.appearance.level)
    }
    #expect(levels == [.compact, .standard, .full, .off])
    var glasses = [StreamDiagnosticsAppearance.Glass]()
    for _ in 0..<5 {
        await store.send(.cycleGlass)
        glasses.append(store.state.appearance.glass)
    }
    #expect(glasses == [.clear, .clearDimmed, .healthTint, .solid, .regular])
    await store.finish()
}

@MainActor @Test func diagnosticsRaiseTheLossBadgeOnlyWhileTheOverlayIsOff() async {
    var state = StreamDiagnosticsReducer.State()
    state.sampling = .running(UUID(0))
    state.appearance.level = .compact
    let store = TestStore(initialState: state) {
        StreamDiagnosticsReducer()
    }
    store.exhaustivity = .off
    for step in 1...6 {
        await store.send(.sampled(UUID(0), sample(step, lost: step * 10)))
    }
    #expect(store.state.lossWarning.visiblePercent == nil)
    await store.send(.selectLevel(.off))
    for step in 7...12 {
        await store.send(.sampled(UUID(0), sample(step, lost: step * 10)))
    }
    #expect(store.state.lossWarning.visiblePercent != nil)
    await store.finish()
}

@Test func diagnosticsHistoryKeepsSixtySecondsAndSumsTheLastTen() {
    var sampler = StreamTelemetrySampler()
    var history = StreamDiagnosticsHistory()
    _ = sampler.update(sample(0))
    for step in 1...150 {
        history.append(sampler.update(sample(step, lost: step)))
    }
    #expect(history.frames.count == StreamDiagnosticsHistory.capacity)
    #expect(history.recent(\.framesLost) == UInt64(StreamDiagnosticsHistory.window))
    #expect(history.recentRate(\.framesLost) == 2)
    #expect(history.marks(.networkLoss).count == StreamDiagnosticsHistory.capacity)
    #expect(history.marks(.audioUnderrun).isEmpty)
}

@Test func diagnosticsAppearanceDecodesUnknownValuesAsDefaults() throws {
    let decoded = try JSONDecoder().decode(
        StreamDiagnosticsAppearance.self,
        from: Data(#"{"level":"huge","glass":"clear"}"#.utf8)
    )
    #expect(decoded == StreamDiagnosticsAppearance(level: .off, glass: .clear, layout: .sheet))
    let floating = try JSONDecoder().decode(
        StreamDiagnosticsAppearance.self,
        from: Data(#"{"level":"full","glass":"solid","layout":"floating"}"#.utf8)
    )
    #expect(floating.layout == .floating)
    let empty = try JSONDecoder().decode(StreamDiagnosticsAppearance.self, from: Data("{}".utf8))
    #expect(empty == StreamDiagnosticsAppearance())
}
