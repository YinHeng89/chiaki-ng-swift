import Foundation
@testable import ChiakiFeatures
import Testing

@Test func theMenuHintOffersTheMenuFromTheContentAndTheTabFromTheMenu() {
    #expect(String(localized: LibraryMenuHint.title(menuFocused: false, section: .consoles)) == "Menu")
    #expect(String(localized: LibraryMenuHint.title(menuFocused: false, section: .cloud)) == "Menu")
    #expect(
        String(localized: LibraryMenuHint.title(menuFocused: true, section: .consoles)) == "Back to Consoles"
    )
    #expect(String(localized: LibraryMenuHint.title(menuFocused: true, section: .cloud)) == "Back to Cloud")
}
