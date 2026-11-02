import Foundation
import Testing
@testable import ChiakiModels

@Test func catalogAndPlusNeverProveStreamability() {
    let evidence = CloudCatalogEvidence(gameCount: 10, nativeCatalog: true, isPlus: true)
    #expect(evidence.availability == .catalogAvailable)
    let date = Date(timeIntervalSince1970: 1000)
    let snapshot = CloudStatusSnapshot(
        scope: .init(accountID: UUID(), locale: "en-GB"), catalog: evidence, checkedAt: date,
        expiresAt: date.addingTimeInterval(900)
    )
    #expect(snapshot.access(for: "game", now: date) == nil)
    #expect(
        CloudCatalogEvidence(gameCount: 10, nativeCatalog: true, isPlus: false).availability
            == .subscriptionRequired
    )
    #expect(
        CloudCatalogEvidence(gameCount: 0, nativeCatalog: true, isPlus: false).availability
            == .empty
    )
    #expect(
        CloudCatalogEvidence(gameCount: 10, nativeCatalog: false, isPlus: nil).availability
            == .limitedCatalog
    )
    #expect(
        CloudCatalogEvidence(
            gameCount: 10, nativeCatalog: true, warning: .sessionExpired, isPlus: true
        ).availability == .signInRequired
    )
}
@Test func gameVerificationExpiresWithoutChangingCatalogAvailability() {
    let date = Date(timeIntervalSince1970: 1000)
    let snapshot = CloudStatusSnapshot(
        scope: .init(accountID: UUID(), locale: "en-GB"),
        catalog: .init(gameCount: 1, nativeCatalog: true, isPlus: true), checkedAt: date,
        expiresAt: date.addingTimeInterval(900),
        games: [
            "game": .init(
                verdict: .streamable, checkedAt: date, expiresAt: date.addingTimeInterval(60)
            )
        ]
    )
    #expect(snapshot.access(for: "game", now: date) == .streamable)
    #expect(snapshot.access(for: "game", now: date.addingTimeInterval(60)) == nil)
    #expect(snapshot.access(for: "other-game", now: date) == nil)
}
