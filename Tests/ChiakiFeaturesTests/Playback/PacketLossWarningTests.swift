import Testing
@testable import ChiakiFeatures

@Test func packetLossWarningNeedsSustainedLossBeforeItShows() {
    var warning = PacketLossWarning()
    warning.sample(5)
    #expect(warning.visiblePercent == nil)
    warning.sample(0.2)
    #expect(warning.phase == .clear)
    warning.sample(3)
    warning.sample(3)
    #expect(warning.visiblePercent == nil)
    warning.sample(4)
    #expect(warning.visiblePercent == 4)
}

@Test func packetLossWarningStaysUpThroughBriefDipsAndClearsAfterSteadyRecovery() {
    var warning = PacketLossWarning()
    warning.sample(3)
    warning.sample(3)
    warning.sample(3)
    warning.sample(1)
    #expect(warning.visiblePercent == 1)
    warning.sample(0.1)
    warning.sample(0.1)
    #expect(warning.visiblePercent == 1)
    warning.sample(2.5)
    #expect(warning.visiblePercent == 2.5)
    for _ in 0..<5 {
        warning.sample(0)
    }
    #expect(warning.visiblePercent == 2.5)
    warning.sample(0)
    #expect(warning.visiblePercent == nil)
    #expect(warning.phase == .clear)
}

@Test func packetLossWarningResetsWhenTheOverlayTakesOver() {
    var warning = PacketLossWarning()
    warning.sample(9)
    warning.sample(9)
    warning.sample(9)
    #expect(warning.visiblePercent == 9)
    warning.reset()
    #expect(warning.visiblePercent == nil)
}
