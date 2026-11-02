@testable import ChiakiFeatures
import Testing

@Test func theMenuHintOffersTheMenuFromTheContentAndTheTabFromTheMenu() {
    #expect(LibraryMenuHint.title(menuFocused: false, section: .consoles) == "Menu")
    #expect(LibraryMenuHint.title(menuFocused: false, section: .cloud) == "Menu")
    #expect(LibraryMenuHint.title(menuFocused: true, section: .consoles) == "Back to Consoles")
    #expect(LibraryMenuHint.title(menuFocused: true, section: .cloud) == "Back to Cloud")
}
