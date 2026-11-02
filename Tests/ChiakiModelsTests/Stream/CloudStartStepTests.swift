import ChiakiModels
import Testing

private let offer = CloudDatacenterLaunchOffer(
    entries: [.init(name: "Tokyo", rttMs: 20)],
    timeoutSeconds: 2
)

@Test func datacenterChoiceCountsDownAndExpires() {
    var choice = CloudDatacenterChoice(offer: offer)
    #expect(choice == .offered(offer, remaining: 2))
    let moved1 = choice.tick()
    #expect(moved1)
    #expect(choice == .offered(offer, remaining: 1))
    let moved2 = choice.tick()
    #expect(moved2)
    #expect(choice == .expired)
    let moved3 = choice.tick()
    #expect(!moved3)
    #expect(choice.offer == nil)
}

@Test func datacenterChoiceSendsOnlyAnOfferedName() {
    var choice = CloudDatacenterChoice(offer: offer)
    let moved4 = choice.choose("Paris")
    #expect(!moved4)
    let moved5 = choice.choose("Tokyo")
    #expect(moved5)
    let moved6 = choice.tick()
    #expect(!moved6)
    let moved7 = choice.sent("Paris", accepted: true)
    #expect(!moved7)
    let moved8 = choice.sent("Tokyo", accepted: false)
    #expect(moved8)
    #expect(choice == .expired)
}

@Test func streamAccessCodeTakesExactlyFourDigitsAndHidesThem() {
    #expect(StreamAccessCode("1234")?.digits == "1234")
    #expect(StreamAccessCode("123") == nil)
    #expect(StreamAccessCode("12a4") == nil)
    #expect(StreamAccessCode("１２３４") == nil)
    #expect(String(reflecting: StreamAccessCode("1234")!) == "[REDACTED]")
}
