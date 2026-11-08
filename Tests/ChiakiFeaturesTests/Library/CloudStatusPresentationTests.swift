import Foundation
import SwiftUI
import Testing
import ChiakiModels
@testable import ChiakiFeatures

@Test @MainActor func cloudPresentationDoesNotShowAnotherAccountsStatus() {
    var state = CloudStatusFeature.State()
    state.scope = .init(accountID: UUID(), locale: "en-GB")
    state.phase = .failed(.signInRequired)
    let result = CloudStatusPresentation(state: state, selectedProfileID: UUID(), now: Date())
    #expect(String(localized: result.text) == "Checking cloud…")
    #expect(result.color == .secondary)
    #expect(!String(localized: result.help).contains("Sign in again"))
}

@Test @MainActor func cloudPresentationUsesOneExpiryBoundary() {
    let id = UUID()
    let now = Date(timeIntervalSince1970: 1000)
    let scope = CloudAccountScope(accountID: id, locale: "en-GB")
    var state = CloudStatusFeature.State()
    state.scope = scope
    state.phase = .ready
    state.snapshot = .init(
        scope: scope,
        catalog: .init(gameCount: 100, nativeCatalog: true, isPlus: true),
        checkedAt: now.addingTimeInterval(-60),
        expiresAt: now
    )
    let result = CloudStatusPresentation(state: state, selectedProfileID: id, now: now)
    #expect(String(localized: result.text) == "Cloud cached result")
    #expect(result.color == .secondary)
    #expect(String(localized: result.help).contains("100 catalog games"))
}

@Test(arguments: [CloudStatusFeature.Phase.idle, .loading(UUID()), .refreshing(UUID())])
@MainActor func cloudPresentationKeepsACurrentResultWhileItChecksAgain(phase: CloudStatusFeature.Phase) {
    let id = UUID()
    let now = Date(timeIntervalSince1970: 1000)
    let scope = CloudAccountScope(accountID: id, locale: "en-GB")
    var state = CloudStatusFeature.State()
    state.scope = scope
    state.phase = phase
    state.snapshot = .init(
        scope: scope,
        catalog: .init(gameCount: 100, nativeCatalog: true, isPlus: true),
        checkedAt: now.addingTimeInterval(-60),
        expiresAt: now.addingTimeInterval(60)
    )
    let current = CloudStatusPresentation(state: state, selectedProfileID: id, now: now)
    #expect(String(localized: current.text) == "Cloud catalog available")
    #expect(current.catalogAvailable)
    let expired = CloudStatusPresentation(
        state: state,
        selectedProfileID: id,
        now: now.addingTimeInterval(60)
    )
    #expect(String(localized: expired.text) == "Checking cloud…")
    state.snapshot = nil
    let unknown = CloudStatusPresentation(state: state, selectedProfileID: id, now: now)
    #expect(String(localized: unknown.text) == "Checking cloud…")
}
