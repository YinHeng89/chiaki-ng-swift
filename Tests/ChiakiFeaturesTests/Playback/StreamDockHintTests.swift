@testable import ChiakiFeatures
import ChiakiModels
import Testing

@Test func theDockHintNamesTheShortcutInTheControllersOwnButtonNames() {
    #expect(
        StreamDockHint.text(shortcut: .standard, family: .playStation)
            == "Press L3 + R3 or point at the bottom for the stream menu"
    )
    #expect(
        StreamDockHint.text(shortcut: .standard, family: .xbox)
            == "Press LS + RS or point at the bottom for the stream menu"
    )
}

@Test func theDockHintOffersThePointerAloneWithoutAController() {
    #expect(StreamDockHint
        .text(shortcut: .standard, family: nil) == "Point at the bottom for the stream menu")
}
