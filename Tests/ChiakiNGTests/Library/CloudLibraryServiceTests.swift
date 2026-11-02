@testable import ChiakiClientsLive
@testable import ChiakiFeatures
import ChiakiModels
@testable import ChiakiNG
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

private func emptySnapshot() throws -> CloudLibrarySnapshot {
    try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[]}
    """.utf8))
}

@MainActor @Test func cloudLibraryReportsACancellationItDidNotAskFor() async throws {
    let account = UUID()
    let attempt = UUID()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .constant(attempt)
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.library = { _, _, _, _ in
            throw CancellationError()
        }
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    await store.receive(\.failed) {
        $0.phase = .failed(.network)
    }
}

@MainActor @Test func stoppingALoadCancelsAPendingRecentlyPlayedFetch() async throws {
    let account = UUID()
    let snapshot = try emptySnapshot()
    let cancelled = LockIsolated(false)
    var state = CloudLibraryFeature.State()
    state.accountID = account
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.continuousClock = TestClock()
        $0.catalog.library = { _, _, _, _ in
            snapshot
        }
        $0.catalog.recentlyPlayed = { _ in
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                cancelled.setValue(true)
                throw error
            }
            return []
        }
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    for _ in 0..<100 {
        await Task.yield()
    }
    await store.send(.stop)
    for _ in 0..<1000 where !cancelled.value {
        await Task.yield()
    }
    #expect(cancelled.value)
    await store.finish()
}
