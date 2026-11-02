import ChiakiDiagnostics
import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func eachGroupOfDroppedTitlesIsLoggedWithItsReason() {
    let snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(
            productId: "EP9000-CUSA07123_00-NIOHEU0000000000",
            name: "Nioh",
            streamServiceType: "psnow"
        ),
        CloudGame(
            productId: "EP3717-CUSA23986_00-CARTO0000000000E", name: "Carto", streamServiceType: "psnow",
            visible: false, hideReason: "not_in_service"
        ),
        CloudGame(
            productId: "EP0001-CUSA05847_00-FARCRY5GAME00000", name: "Far Cry 5", streamServiceType: "psnow",
            visible: false, hideReason: "not_in_service"
        ),
        CloudGame(
            productId: "UP9000-PPSA00001_00-EDITION000000000", name: "Edition", visible: false,
            hideReason: "already_owned"
        )
    ])

    #expect(CloudLibraryLog.dropped(snapshot) == [
        "Dropped 2 PS Now title(s) because no PlayStation Plus plan covers the title's streaming copy: "
            + "\"Carto\" (EP3717-CUSA23986_00-CARTO0000000000E), "
            + "\"Far Cry 5\" (EP0001-CUSA05847_00-FARCRY5GAME00000)",
        "Dropped 1 PS Cloud title(s) because an edition already in the library covers it: "
            + "\"Edition\" (UP9000-PPSA00001_00-EDITION000000000)"
    ])
}

@Test func aLongGroupOfDroppedTitlesNamesTheFirstAndCountsTheRest() {
    let games = (0..<45).map {
        CloudGame(
            productId: "EP0001-CUSA\(10000 + $0)_00-GAME000000000000", name: "Game \($0)",
            streamServiceType: "psnow", visible: false, hideReason: "tier_does_not_include"
        )
    }
    let lines = CloudLibraryLog.dropped(CloudLibrarySnapshot(settledLocale: "en-GB", games: games))

    #expect(lines.count == 1)
    #expect(lines[0]
        .hasPrefix("Dropped 45 PS Now title(s) because the membership tier does not include streaming"))
    #expect(lines[0].contains("\"Game 39\""))
    #expect(!lines[0].contains("\"Game 40\""))
    #expect(lines[0].hasSuffix(", and 5 more"))
}

@Test func nothingIsLoggedWhenNothingIsDropped() {
    let snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "EP9000-CUSA07123_00-NIOHEU0000000000", name: "Nioh", streamServiceType: "psnow")
    ])

    #expect(CloudLibraryLog.dropped(snapshot).isEmpty)
}

@Test
func anOwnedPS5CopyThatDoesNotStreamIsNamedWithItsReason() {
    let games = [
        CloudGame(
            productId: "EP0002-PPSA23013_00-MWII000000000000", name: "Modern Warfare II",
            streamServiceType: "pscloud", visible: false, hideReason: "copy_does_not_stream"
        )
    ]
    let lines = CloudLibraryLog.dropped(CloudLibrarySnapshot(settledLocale: "en-GB", games: games))

    #expect(lines == [
        "Dropped 1 PS Cloud title(s) because the store says the owned PS5 copy does not support streaming: "
            + "\"Modern Warfare II\" (EP0002-PPSA23013_00-MWII000000000000)"
    ])
}
