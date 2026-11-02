import ChiakiModels
import Testing

private func state(menu: Bool, screenOn: Bool, hidden: Bool, backgroundInput: Bool) -> CloudSystemUIState {
    CloudSystemUIState(
        menuCoversStream: menu,
        screenOn: screenOn,
        appHidden: hidden,
        backgroundInput: backgroundInput
    )
}

@Test func aScreenThatIsOffIsInTheBackgroundEvenUnderTheMenu() {
    #expect(state(menu: false, screenOn: true, hidden: false, backgroundInput: false) == .game)
    #expect(state(menu: true, screenOn: true, hidden: false, backgroundInput: false) == .overlaid)
    #expect(state(menu: false, screenOn: false, hidden: false, backgroundInput: true) == .background)
    #expect(state(menu: true, screenOn: false, hidden: false, backgroundInput: true) == .background)
}

@Test func aHiddenAppIsInTheBackgroundOnlyWithoutBackgroundInput() {
    #expect(state(menu: false, screenOn: true, hidden: true, backgroundInput: false) == .background)
    #expect(state(menu: true, screenOn: true, hidden: true, backgroundInput: false) == .background)
    #expect(state(menu: false, screenOn: true, hidden: true, backgroundInput: true) == .game)
    #expect(state(menu: true, screenOn: true, hidden: true, backgroundInput: true) == .overlaid)
}
