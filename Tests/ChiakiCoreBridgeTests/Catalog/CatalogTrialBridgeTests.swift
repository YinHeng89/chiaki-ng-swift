import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct CatalogTrialBridgeTests {
    @Test func aStoreGameCarriesTheTrialVersionItOffers() {
        var facts = chiaki_bridge.GameFacts()
        facts.product_id = std.string("UP1675-PPSA36389_00-SYPS5HAILTOTHERA")
        facts.platform = .ps5
        facts.service = .ps5_cloud
        facts.ownership = .not_owned
        facts.standing = .store
        #expect(CloudGameReader.game(of: facts).trialOffer == nil)
        facts.trial_offer = .play_first_trial
        #expect(CloudGameReader.game(of: facts).trialOffer == .playFirstTrial)
        facts.trial_offer = .demo
        let game = CloudGameReader.game(of: facts)
        #expect(game.trialOffer == .demo)
        #expect(!game.isTrial)
    }

    @Test func aStorefrontAnswerSaysWhetherATrialIsStillOffered() {
        var answer = chiaki_bridge.StorefrontFacts()
        answer.streaming = libchiaking.catalog.StorefrontAnswer.Streaming.streams
        let unasked = chiaki_bridge.StorefrontOutcome.answered(answer)
        #expect((try? TitleChecksBridge.result(of: unasked).get())?.offersTrial == .some(nil))
        answer.offers_trial = .init(false)
        let withdrawn = chiaki_bridge.StorefrontOutcome.answered(answer)
        #expect((try? TitleChecksBridge.result(of: withdrawn).get())?.offersTrial == false)
        answer.offers_trial = .init(true)
        let offered = chiaki_bridge.StorefrontOutcome.answered(answer)
        #expect((try? TitleChecksBridge.result(of: offered).get())?.offersTrial == true)
    }
}
