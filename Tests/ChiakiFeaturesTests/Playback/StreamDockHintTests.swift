@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

@Test func theDockHintNamesTheShortcutInTheControllersOwnButtonNames() {
    #expect(
        String(localized: StreamDockHint.text(shortcut: .standard, family: .playStation))
            == "Press L3 + R3 or point at the bottom for the stream menu"
    )
    #expect(
        String(localized: StreamDockHint.text(shortcut: .standard, family: .xbox))
            == "Press LS + RS or point at the bottom for the stream menu"
    )
}

@Test func theDockHintOffersThePointerAloneWithoutAController() {
    #expect(String(localized: StreamDockHint
            .text(shortcut: .standard, family: nil)) == "Point at the bottom for the stream menu")
}
