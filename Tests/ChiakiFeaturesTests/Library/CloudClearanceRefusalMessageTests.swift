import ChiakiModels
import Testing
@testable import ChiakiFeatures

@Test func theEntitlementRefusalsSayWhatHappenedToTheCopy() {
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: .invalidTitle))
            == "PlayStation has no record of your copy of this title."
    )
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: .titleTakenDown))
            == "This title has been taken down from cloud streaming."
    )
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: .streamingUnavailable))
            == "Cloud streaming isn’t available for your copy of this title."
    )
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(
            refusal: .purchaseNeeded,
            price: "£9.99"
        ))
            == "Your copy of this title is no longer active. "
            + "Buy it again on PlayStation Store to stream it (£9.99)."
    )
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: .unexpectedEntitlementState))
            == "PlayStation reports your copy of this title in a state that can’t be streamed."
    )
    #expect(
        CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: .chooseAGame))
            == "Choose one of the games in this bundle to play."
    )
}
