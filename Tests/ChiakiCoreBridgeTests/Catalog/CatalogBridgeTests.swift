import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct CatalogBridgeTests {
    private static let image = "https://image.api.playstation.com/"

    private static func texts(_ values: [String]) -> chiaki_bridge.Texts {
        var list = chiaki_bridge.Texts()
        for value in values {
            list.push_back(std.string(value))
        }
        return list
    }

    @Test func fullDetailsBecomeTheModelDetails() {
        var facts = chiaki_bridge.GameDetailsFacts()
        facts.background_url = .init(std.string(Self.image + "background.png"))
        facts.hero_url = .init(std.string(Self.image + "hero.png"))
        facts.logo_url = .init(std.string(Self.image + "logo.png"))
        facts.screenshot_urls = Self.texts([Self.image + "one.jpg"])
        facts.trailer_urls = Self.texts(["https://vulcan.dl.playstation.net/trailer.mp4"])
        facts.star_average = .init(4.74)
        facts.star_average_text = std.string("4.74")
        facts.star_ratings = 216_539
        for share: Int32 in [2, 1, 3, 8, 86] {
            facts.star_percent.push_back(share)
        }
        facts.age_authority = .init(std.string("PEGI"))
        facts.age_name = std.string("PEGI 16")
        facts.age_description = std.string("Ages 16 and over")
        facts.age_icon_url = .init(std.string(Self.image + "pegi.png"))
        facts.age_descriptors = Self.texts(["Violence"])
        facts.publisher = std.string("Sony Interactive Entertainment")
        facts.released_ms = .init(1_730_332_800_000)
        facts.genres = Self.texts(["Role Playing Games", "Action"])
        let details = GameDetailsReader.details(of: facts)
        #expect(details.layeredArt == .init(
            background: Self.image + "background.png",
            hero: Self.image + "hero.png",
            logo: Self.image + "logo.png"
        ))
        #expect(details.screenshots == [Self.image + "one.jpg"])
        #expect(details.trailers.map(\.absoluteString) == ["https://vulcan.dl.playstation.net/trailer.mp4"])
        #expect(details.starRating == .init(
            average: 4.74,
            averageText: "4.74",
            ratings: 216_539,
            percentByStars: [2, 1, 3, 8, 86]
        ))
        #expect(details.ageRating == .init(
            authority: "PEGI",
            name: "PEGI 16",
            description: "Ages 16 and over",
            icon: Self.image + "pegi.png",
            descriptors: ["Violence"]
        ))
        #expect(details.publisher == "Sony Interactive Entertainment")
        #expect(details.releasedAt == Date(timeIntervalSince1970: 1_730_332_800))
        #expect(details.genres == ["Role Playing Games", "Action"])
    }

    @Test func emptyDetailsInventNothing() {
        #expect(GameDetailsReader.details(of: chiaki_bridge.GameDetailsFacts()) == GameDetails())
        var facts = chiaki_bridge.GameDetailsFacts()
        facts.background_url = .init(std.string(Self.image + "background.png"))
        facts.hero_url = .init(std.string(Self.image + "hero.png"))
        #expect(GameDetailsReader.details(of: facts).art == nil)
    }

    @Test func aGameHubCoverBecomesGameHubArt() {
        var facts = chiaki_bridge.GameDetailsFacts()
        facts.game_hub_cover_url = .init(std.string(Self.image + "cover.png"))
        facts.logo_url = .init(std.string(Self.image + "logo.png"))
        #expect(GameDetailsReader.details(of: facts).art == .gameHub(.init(
            cover: Self.image + "cover.png",
            logo: Self.image + "logo.png"
        )))
        facts.logo_url = .init()
        #expect(GameDetailsReader.details(of: facts).art == .gameHub(.init(cover: Self.image + "cover.png")))
        facts.background_url = .init(std.string(Self.image + "background.png"))
        facts.hero_url = .init(std.string(Self.image + "hero.png"))
        facts.logo_url = .init(std.string(Self.image + "logo.png"))
        #expect(GameDetailsReader.details(of: facts).art == .layered(.init(
            background: Self.image + "background.png",
            hero: Self.image + "hero.png",
            logo: Self.image + "logo.png"
        )))
    }

    @Test func aBundleCrossesWithItsGamesAndTheCoreVerdictOnEach() {
        let first = "EP9000-PPSA00002_00-FIRSTGAME0000000"
        let second = "EP9000-PPSA00003_00-SECONDGAME000000"
        var facts = chiaki_bridge.GameFacts()
        facts.product_id = std.string("EP9000-PPSA00001_00-BUNDLE0000000000")
        facts.name = std.string("Double Pack")
        facts.ownership_id = .init(std.string(first))
        facts.launch_refusal = .init(libchiaking.catalog.LaunchRefusal.Kind.choose_a_game)
        facts.is_bundle = true
        facts.bundle_owned = true
        var owned = chiaki_bridge.BundledGameFacts()
        owned.product_id = .init(std.string(first))
        owned.entitlement_id = std.string(first)
        owned.owned = true
        var unowned = chiaki_bridge.BundledGameFacts()
        unowned.product_id = .init(std.string(second))
        unowned.entitlement_id = std.string(second)
        unowned.launch_refusal = .init(libchiaking.catalog.LaunchRefusal.Kind.add_to_library)
        var unshaped = chiaki_bridge.BundledGameFacts()
        unshaped.entitlement_id = std.string("unshaped")
        facts.children.push_back(owned)
        facts.children.push_back(unowned)
        facts.children.push_back(unshaped)
        let game = CloudGameReader.game(of: facts)
        #expect(game.isBundle)
        #expect(game.ownershipId == first)
        #expect(game.launchRefusal == .chooseAGame)
        #expect(game.bundle == CloudBundle(isOwned: true, games: [
            CloudBundledGame(productId: first, entitlementId: first, isOwned: true),
            CloudBundledGame(
                productId: second,
                entitlementId: second,
                isOwned: false,
                launchRefusal: .addToLibrary
            )
        ]))
        facts.is_bundle = false
        #expect(CloudGameReader.game(of: facts).bundle == nil)
    }

    @Test func aTitleCarriesItsPlatformServiceAndStanding() {
        var facts = chiaki_bridge.GameFacts()
        facts.product_id = std.string("UP9000-CUSA00001_00-OLDSERVICE000000")
        facts.platform = .ps4
        facts.service = .old_service
        facts.ownership = .owned
        facts.standing = .in_library
        facts.hide_reason = .init(libchiaking.catalog.HideReason.tier_does_not_include)
        facts.release = .scheduled
        facts.release_ms = .init(1_730_332_800_000)
        let game = CloudGameReader.game(of: facts)
        #expect(game.platform == "PS4")
        #expect(game.streamServiceType == "psnow")
        #expect(game.isOwned)
        #expect(game.standing == .inLibrary)
        #expect(game.hideReason == "tier_does_not_include")
        #expect(game.release == .scheduled(Date(timeIntervalSince1970: 1_730_332_800)))
        #expect(game.imageUrl == nil)
    }

    @Test func aTrialCopyCrossesAsATrial() {
        var facts = chiaki_bridge.GameFacts()
        facts.product_id = std.string("EP9000-PPSA00004_00-TRIAL000000000000")
        facts.platform = .ps5
        facts.service = .ps5_cloud
        facts.ownership = .owned
        #expect(!CloudGameReader.game(of: facts).isTrial)
        facts.is_trial = true
        let game = CloudGameReader.game(of: facts)
        #expect(game.isTrial)
        #expect(game.isOwnedPS5)
    }

    @Test func anEndedTrialCrossesAsATrialThatCannotLaunch() {
        var facts = chiaki_bridge.GameFacts()
        facts.product_id = std.string("EP9000-PPSA00005_00-PLAYFIRST0000000")
        facts.platform = .ps5
        facts.service = .ps5_cloud
        facts.ownership = .owned
        facts.is_trial = true
        #expect(!CloudGameReader.game(of: facts).trialEnded)
        #expect(!CloudGameReader.game(of: facts).isPlayFirstTrial)
        facts.trial_ended = true
        facts.is_play_first_trial = true
        facts.launch_refusal = .init(libchiaking.catalog.LaunchRefusal.Kind.purchase_needed)
        let game = CloudGameReader.game(of: facts)
        #expect(game.isTrial)
        #expect(game.trialEnded)
        #expect(game.isPlayFirstTrial)
        #expect(game.launchRefusal == .purchaseNeeded)
    }

    @Test func aRefusalBeforeTheCoreRanBecomesItsReason() {
        let unknownConcept = chiaki_bridge.DetailsOutcome
            .refused(chiaki_bridge.CatalogRefusal.invalid_concept)
        #expect(TitleChecksBridge
            .result(of: unknownConcept) == .failure(CatalogUnanswered(reason: .invalidConcept)))
        let closed = chiaki_bridge.DetailsOutcome.refused(chiaki_bridge.CatalogRefusal.core_closed)
        #expect(TitleChecksBridge.result(of: closed) == .failure(CatalogUnanswered(reason: .coreClosed)))
    }

    @Test func anUnansweredRequestKeepsItsStatusAndSignIn() {
        let outcome = chiaki_bridge.ImageOutcome.unanswered(chiaki_bridge.CatalogUnanswered(
            reason: .restriction_list_unavailable,
            http_status: 503,
            needs_sign_in: true
        ))
        #expect(TitleChecksBridge.result(of: outcome) == .failure(CatalogUnanswered(
            reason: .restrictionListUnavailable,
            httpStatus: 503,
            needsSignIn: true
        )))
    }

    @Test func aRefusedLaunchCarriesItsNoticeTimeAndSignIn() throws {
        var decline = chiaki_bridge.LaunchDeclineFacts()
        decline.kind = libchiaking.catalog.LaunchRefusal.Kind.not_released
        decline.time_ms = .init(1_730_332_800_000)
        decline.notice = std.string("Soon")
        let clearance = try TitleChecksBridge.result(of: chiaki_bridge.ClearanceOutcome.declined(decline))
            .get()
        #expect(clearance == .refused(CloudClearanceRefusal(
            refusal: .notReleased,
            notice: "Soon",
            time: Date(timeIntervalSince1970: 1_730_332_800)
        )))
        #expect(try TitleChecksBridge
            .result(of: chiaki_bridge.ClearanceOutcome.cleared(chiaki_bridge.ClearedFacts()))
            .get() == .cleared(nil))
    }

    @Test func aFetchReportKeepsWhatTheCoreKnew() {
        var facts = chiaki_bridge.FetchFacts()
        facts.from_account_service = true
        facts.complete = false
        facts.fetched_at_ms = 1_000
        facts.copies_asked = .init(4)
        facts.copies_answered = .init(3)
        facts.audience_country = .init(std.string("GB"))
        facts.audience_language = .init(std.string("en"))
        facts.audience_age = .init(30)
        facts.library = .init(libchiaking.catalog.LibraryState.partial)
        facts.library_fetched_at_ms = .init(2_000)
        facts.library_records = 7
        facts.tier = .init(libchiaking.users.Tier.premium)
        let report = CatalogExplanationReader.report(of: facts)
        #expect(!report.complete)
        #expect(report.listFetchedAt == Date(timeIntervalSince1970: 1))
        #expect(report.copiesChecked == .init(asked: 4, answered: 3))
        #expect(report.audience == .init(country: "GB", language: "en", age: 30))
        #expect(report.premiumCategory == nil)
        #expect(report.library == .fetched(Date(timeIntervalSince1970: 2), records: 7))
        #expect(report.tier == .premium)
        #expect(CatalogExplanationReader.report(of: chiaki_bridge.FetchFacts()).library == .unknown)
    }

    @Test func aFetchStateKeepsEveryFieldTheCoreReported() {
        var facts = chiaki_bridge.FetchStateFacts()
        facts.attempt = 3
        facts.step = .owned_library
        facts.activity = .init(libchiaking.catalog.FetchActivity.scanning_ps5_library)
        facts.pages_read = 4
        facts.pages_expected = .init(9)
        var signIn = libchiaking.catalog.PassedStep()
        signIn.step = .checking_sign_in
        signIn.outcome = .held
        var list = libchiaking.catalog.PassedStep()
        list.step = .cloud_list
        list.outcome = .degraded
        facts.passed.push_back(signIn)
        facts.passed.push_back(list)
        facts.running = true
        #expect(CatalogFetchStateReader.state(of: facts) == CloudLibraryFetchState(
            attempt: 3,
            step: .ownedLibrary,
            activity: .scanningPS5Library,
            pagesRead: 4,
            pagesExpected: 9,
            passed: [
                .init(step: .checkingSignIn, outcome: .held),
                .init(step: .cloudList, outcome: .degraded)
            ],
            isRunning: true
        ))
    }

    @Test func aClockSyncKeepsTheTimeServerTheCoreAsks() {
        var facts = chiaki_bridge.FetchStateFacts()
        facts.attempt = 2
        facts.step = .trusted_time
        facts.activity = .init(libchiaking.catalog.FetchActivity.syncing_clock)
        facts.time_server = .init(std.string("time3.google.com"))
        facts.running = true
        #expect(CatalogFetchStateReader.state(of: facts).activity == .syncingClock(host: "time3.google.com"))
        facts.time_server = .init()
        #expect(CatalogFetchStateReader.state(of: facts).activity == .syncingClock(host: nil))
    }

    @Test func anUnansweredFetchStateKeepsItsFailure() {
        var facts = chiaki_bridge.FetchStateFacts()
        facts.attempt = 1
        facts.step = .unanswered
        facts.failure = .init(chiaki_bridge.CatalogUnanswered(
            reason: .user,
            http_status: 401,
            needs_sign_in: true
        ))
        let state = CatalogFetchStateReader.state(of: facts)
        #expect(state.step == .unanswered)
        #expect(state.activity == nil)
        #expect(state.pagesExpected == nil)
        #expect(!state.isRunning)
        #expect(state.failure == CatalogFailure(reason: .user, httpStatus: 401, needsSignIn: true))
        #expect(state.failure?.libraryFailure == .signInRequired)
    }

    @Test func everyCoreFetchStepAndActivityHasItsOwnModelValue() {
        let steps: [libchiaking.catalog.FetchStep] = [
            .idle, .checking_sign_in, .cloud_list, .owned_library, .premium_category, .for_sale_category,
            .streaming_access, .matching, .trusted_time, .exclusions, .ready, .unanswered, .cancelled
        ]
        #expect(steps.map(CatalogFetchStateReader.step(of:)) == CloudLibraryFetchState.Step.allCases)
        let activities: [libchiaking.catalog.FetchActivity] = [
            .reusing_held_answer, .walking_public_store, .walking_old_service_shelves,
            .walking_public_store_fallback, .checking_streaming_copies, .reading_ps5_store_lists,
            .reading_entitlements, .reading_streamed_ps4_concepts, .scanning_ps5_library,
            .reading_category_pages, .reading_subscriptions, .matching_games, .syncing_clock,
            .reading_exclusions
        ]
        #expect(activities.map { CatalogFetchStateReader.activity(of: $0) } == CloudLibraryFetchState.Activity
            .allCases)
        let outcomes: [libchiaking.catalog.StepOutcome] = [.skipped, .held, .fetched, .degraded]
        #expect(outcomes.map(CatalogFetchStateReader.outcome(of:)) == CloudLibraryFetchState.Outcome.allCases)
    }
}
