import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads an account's cloud catalog through the open core: its titles, why each is listed, how the list was
/// fetched and whether cloud streaming is available.
///
/// Requests that reach PSN block a core thread, so they run on a dispatch queue while the calling task waits;
/// cancelling the task cancels the core request.
public struct CatalogBridge: Sendable {
    private final class FetchObserver: @unchecked Sendable {
        let observe: @Sendable (CloudLibraryFetchState) -> Void

        init(_ observe: @escaping @Sendable (CloudLibraryFetchState) -> Void) {
            self.observe = observe
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// The account's cloud titles, visible ones first.
    ///
    /// The core runs one fetch per account: a call made while one runs joins it, is told its current state at
    /// once and gets the same titles.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - startOver: Whether to drop what the catalog holds and fetch everything again.
    ///   - observe: Told every state of the fetch this call leads or joins, in order, on a core thread, and
    ///     never after this returns.
    /// - Returns: Every title, visible or hidden.
    /// - Throws: The ``CatalogUnanswered`` that stopped the fetch.
    public func myGames(
        account: AccountID,
        startOver: Bool,
        observe: @escaping @Sendable (CloudLibraryFetchState) -> Void = { _ in
        }
    ) async throws(CatalogUnanswered) -> [CloudGame] {
        let observer = FetchObserver(observe)
        let result = await CoreCancellation.run(qos: .utility) { request in
            withExtendedLifetime(observer) {
                Self.result(of: chiaki_bridge.CatalogBridge.my_games(
                    request,
                    UsersBridge.vector(account),
                    startOver,
                    { state, context in
                        guard let state, let context else {
                            return
                        }
                        Unmanaged<FetchObserver>.fromOpaque(context).takeUnretainedValue()
                            .observe(CatalogFetchStateReader.state(of: state.pointee))
                    },
                    Unmanaged.passUnretained(observer).toOpaque()
                ))
            }
        }
        return try result.get()
    }

    /// Where the account's latest full catalog fetch stands, running or ended, without asking PlayStation
    /// anything.
    ///
    /// - Parameter account: The account.
    /// - Returns: The latest state, or `nil` when the core is closed or does not know the account.
    public func fetchState(account: AccountID) -> CloudLibraryFetchState? {
        chiaki_bridge.CatalogBridge.fetch_state(UsersBridge.vector(account)).value
            .map(CatalogFetchStateReader.state(of:))
    }

    /// The cloud titles the account played recently.
    ///
    /// - Parameter account: The account.
    /// - Returns: The titles, most recent first.
    /// - Throws: The ``CatalogUnanswered`` that stopped the listing.
    public func recentlyPlayed(account: AccountID) async throws(CatalogUnanswered) -> [CloudRecentlyPlayed] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.CatalogBridge.recently_played(request, UsersBridge.vector(account)))
        }
        return try result.get()
    }

    /// Checks again whether the account owns one title.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - game: The title.
    /// - Returns: What the check found.
    public func refreshTitle(account: AccountID, game: CloudGame) async -> CloudTitleRefreshOutcome {
        let product = game.productId
        return await CoreCancellation.run { request in
            Self.refreshed(chiaki_bridge.CatalogBridge.recheck_ownership(
                request,
                UsersBridge.vector(account),
                std.string(product)
            ))
        }
    }

    /// Why the catalog listed or hid one title.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - productID: The title's product id.
    /// - Returns: The explanation, or `nil` when the core is closed or does not know the user or product.
    public func explain(account: AccountID, productID: String) -> CatalogExplanation? {
        chiaki_bridge.CatalogBridge.explain(UsersBridge.vector(account), std.string(productID)).value
            .map(CatalogExplanationReader.explanation(of:))
    }

    /// The PS5 cloud games the account holds as a trial or demo, from what the core already holds, including its
    /// saved library; asks the store nothing.
    ///
    /// - Parameter account: The account.
    /// - Returns: The held trials, or none when nothing is held or the core is closed.
    public func heldTrials(account: AccountID) -> [CloudGame] {
        chiaki_bridge.CatalogBridge.held_trials(UsersBridge.vector(account)).map(CloudGameReader.game(of:))
    }

    /// How the catalog last fetched the account's titles.
    ///
    /// - Parameter account: The account.
    /// - Returns: The report, or `nil` when nothing was fetched yet.
    public func howFetched(account: AccountID) -> CatalogFetchReport? {
        chiaki_bridge.CatalogBridge.how_fetched(UsersBridge.vector(account)).value
            .map(CatalogExplanationReader.report(of:))
    }

    /// Whether the account can use cloud streaming.
    ///
    /// - Parameter account: The account.
    /// - Returns: What the check found.
    /// - Throws: The ``CatalogUnanswered`` that stopped the check.
    public func cloudAccess(account: AccountID) async throws(CatalogUnanswered) -> CloudAccess {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.CatalogBridge.cloud_access(request, UsersBridge.vector(account)))
        }
        return try result.get()
    }

    /// Where one capture in the account's cloud media gallery can be downloaded.
    ///
    /// - Parameters:
    ///   - account: The account whose gallery holds the capture.
    ///   - galleryID: The capture's id in the gallery.
    /// - Returns: The capture's signed download address, or `nil` when PSN did not name it.
    /// - Throws: The ``CatalogUnanswered`` that stopped the lookup.
    public func cloudCapture(
        account: AccountID,
        galleryID: String
    ) async throws(CatalogUnanswered) -> CloudCaptureFile? {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.CatalogBridge.cloud_capture(
                request,
                UsersBridge.vector(account),
                std.string(galleryID)
            ))
        }
        return try result.get()
    }

    /// Whether the account's PlayStation setting downloads cloud captures to devices.
    ///
    /// - Parameter account: The account.
    /// - Returns: Whether captures are downloaded.
    /// - Throws: The ``CatalogUnanswered`` that stopped the lookup.
    public func cloudCaptureDownload(account: AccountID) async throws(CatalogUnanswered) -> Bool {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.CatalogBridge.cloud_capture_download(
                request,
                UsersBridge.vector(account)
            ))
        }
        return try result.get()
    }

    /// The model result of a capture lookup.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The capture's address, `nil` when none was named, or the failure.
    static func result(
        of outcome: chiaki_bridge.CaptureFileOutcome
    ) -> Result<CloudCaptureFile?, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            let facts = outcome.file()
            guard let url = URL(string: String(facts.url)) else {
                return .success(nil)
            }
            return .success(CloudCaptureFile(url: url, fileType: String(facts.file_type), size: facts.size))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a capture setting lookup.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: Whether captures are downloaded, or the failure.
    static func result(of outcome: chiaki_bridge.CaptureDownloadOutcome) -> Result<Bool, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(outcome.downloads())
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a title listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The titles or the failure.
    static func result(of outcome: chiaki_bridge.GamesOutcome) -> Result<[CloudGame], CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(outcome.games().map(CloudGameReader.game(of:)))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a recently played listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The titles or the failure.
    static func result(
        of outcome: chiaki_bridge.PlayedOutcome
    ) -> Result<[CloudRecentlyPlayed], CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(outcome.played().map {
                CloudRecentlyPlayed(productId: String($0.product_id), lastPlayed: date(of: $0.last_played_ms))
            })
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a cloud access check.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The access or the failure.
    static func result(of outcome: chiaki_bridge
        .CloudAccessOutcome) -> Result<CloudAccess, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            let access = outcome.access()
            return .success(CloudAccess(
                availability: availability(of: access.availability),
                titleCount: access.title_count.value.map { Int($0) },
                complete: access.complete,
                fromAccountService: access.from_account_service
            ))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model outcome of an ownership recheck.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: What the check found.
    static func refreshed(_ outcome: chiaki_bridge.OwnershipOutcome) -> CloudTitleRefreshOutcome {
        switch outcome.kind() {
        case .answered:
            return refreshed(outcome.ownership())
        case .unanswered:
            return failed(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return failed(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model outcome of an ownership recheck the failure stopped.
    ///
    /// - Parameter failure: Why the check found nothing.
    /// - Returns: The failed outcome.
    static func failed(_ failure: CatalogUnanswered) -> CloudTitleRefreshOutcome {
        if failure.reason == .cancelled {
            return .failed(.cancelled)
        }
        return .failed(failure.needsSignIn
            ? .signInRefused
            : .checkFailed)
    }

    /// The model outcome of an ownership recheck the catalog answered.
    ///
    /// - Parameter ownership: What the check found.
    /// - Returns: What the check found, as the library shows it.
    static func refreshed(_ ownership: chiaki_bridge.OwnershipFacts) -> CloudTitleRefreshOutcome {
        guard ownership.answer == .owned else {
            return .notOwned
        }
        guard let owned = ownership.game.value else {
            return .failed(.titleMissing)
        }
        return .owned(CloudGameReader.game(of: owned))
    }

    /// The model availability of the core's.
    ///
    /// - Parameter availability: The core's availability.
    /// - Returns: The model value.
    static func availability(
        of availability: libchiaking.catalog.CloudAccess.Availability
    ) -> CloudAccess.Availability {
        switch availability {
        case .available:
            .available
        case .sign_in_expired:
            .signInExpired
        case .access_rejected:
            .rejected
        case .region_unsupported:
            .regionUnsupported
        case .unavailable:
            .unavailable
        }
    }

    /// A moment given in milliseconds since 1970.
    ///
    /// - Parameter milliseconds: The moment.
    /// - Returns: The date.
    static func date(of milliseconds: Int64) -> Date {
        Timestamp.date(milliseconds: milliseconds)
    }

    /// A text, or `nil` when it is empty.
    ///
    /// - Parameter value: The text.
    /// - Returns: The text when it is not empty.
    static func text(_ value: String) -> String? {
        value.isEmpty
            ? nil
            : value
    }
}

/// Reads the states the core reports for a full catalog fetch.
enum CatalogFetchStateReader {
    /// The model state of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The state, field by field.
    static func state(of facts: chiaki_bridge.FetchStateFacts) -> CloudLibraryFetchState {
        CloudLibraryFetchState(
            attempt: facts.attempt,
            step: step(of: facts.step),
            activity: facts.activity.value.map { reported in
                activity(of: reported, timeServer: facts.time_server.value.map(String.init))
            },
            pagesRead: Int(facts.pages_read),
            pagesExpected: facts.pages_expected.value.map { Int($0) },
            passed: facts.passed.map { passed in
                CloudLibraryFetchState.PassedStep(
                    step: step(of: passed.step),
                    outcome: outcome(of: passed.outcome)
                )
            },
            failure: facts.failure.value.map { CatalogFailure(CatalogUnanswered.of($0)) },
            isRunning: facts.running
        )
    }

    /// The model step of the core's.
    ///
    /// - Parameter step: The core's step.
    /// - Returns: The model step.
    static func step(of step: libchiaking.catalog.FetchStep) -> CloudLibraryFetchState.Step {
        switch step {
        case .idle:
            .idle
        case .checking_sign_in:
            .checkingSignIn
        case .cloud_list:
            .cloudList
        case .owned_library:
            .ownedLibrary
        case .premium_category:
            .premiumCategory
        case .for_sale_category:
            .forSaleCategory
        case .streaming_access:
            .streamingAccess
        case .matching:
            .matching
        case .trusted_time:
            .trustedTime
        case .exclusions:
            .exclusions
        case .ready:
            .ready
        case .unanswered:
            .unanswered
        case .cancelled:
            .cancelled
        }
    }

    /// The model activity of the core's.
    ///
    /// - Parameters:
    ///   - activity: The core's activity.
    ///   - timeServer: The time server the core reported asking, for a clock sync.
    /// - Returns: The model activity.
    static func activity(
        of activity: libchiaking.catalog.FetchActivity,
        timeServer: String? = nil
    ) -> CloudLibraryFetchState.Activity {
        switch activity {
        case .reusing_held_answer:
            .reusingHeldAnswer
        case .walking_public_store:
            .walkingPublicStore
        case .walking_old_service_shelves:
            .walkingOldServiceShelves
        case .walking_public_store_fallback:
            .walkingPublicStoreFallback
        case .checking_streaming_copies:
            .checkingStreamingCopies
        case .reading_ps5_store_lists:
            .readingPS5StoreLists
        case .reading_entitlements:
            .readingEntitlements
        case .reading_streamed_ps4_concepts:
            .readingStreamedPS4Concepts
        case .scanning_ps5_library:
            .scanningPS5Library
        case .reading_category_pages:
            .readingCategoryPages
        case .reading_subscriptions:
            .readingSubscriptions
        case .matching_games:
            .matchingGames
        case .syncing_clock:
            .syncingClock(host: timeServer)
        case .reading_exclusions:
            .readingExclusions
        }
    }

    /// The model outcome of the core's.
    ///
    /// - Parameter outcome: The core's outcome.
    /// - Returns: The model outcome.
    static func outcome(of outcome: libchiaking.catalog.StepOutcome) -> CloudLibraryFetchState.Outcome {
        switch outcome {
        case .skipped:
            .skipped
        case .held:
            .held
        case .fetched:
            .fetched
        case .degraded:
            .degraded
        }
    }
}

/// Reads the core's explanations of the catalog: why a title is listed or hidden, and how the list was
/// fetched.
enum CatalogExplanationReader {
    /// The model explanation of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The explanation.
    static func explanation(of facts: chiaki_bridge.ExplanationFacts) -> CatalogExplanation {
        CatalogExplanation(listed: facts.listed, steps: facts.steps.map { step in
            CatalogExplanation.Step(
                rule: rule(of: step.rule),
                outcome: outcome(of: step.outcome),
                hides: step.hides,
                productID: step.product_id.value.map { String($0) },
                ownershipID: step.ownership_id.value.map { String($0) },
                titleNumber: step.title_number.value.map { String($0) },
                tier: step.tier.value.map(UsersBridge.tier(of:))
            )
        })
    }

    /// The model fetch report of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The report.
    static func report(of facts: chiaki_bridge.FetchFacts) -> CatalogFetchReport {
        var report = CatalogFetchReport()
        report.fromAccountService = facts.from_account_service
        report.complete = facts.complete
        report.listFetchedAt = CatalogBridge.date(of: facts.fetched_at_ms)
        report.psNowTitles = Int(facts.ps_now_titles)
        if let asked = facts.copies_asked.value, let answered = facts.copies_answered.value {
            report.copiesChecked = .init(asked: Int(asked), answered: Int(answered))
        }
        report.withoutACoveredCopy = Int(facts.without_a_covered_copy)
        report.psCloudTitles = Int(facts.ps_cloud_titles)
        if let country = facts.audience_country.value, let language = facts.audience_language.value,
           let age = facts.audience_age.value {
            report.audience = .init(country: String(country), language: String(language), age: Int(age))
        }
        if let fetched = facts.premium_category_fetched_at_ms.value,
           let titles = facts.premium_category_titles.value {
            report.premiumCategory = .init(fetchedAt: CatalogBridge.date(of: fetched), titles: Int(titles))
        }
        report.library = library(of: facts.library.value, at: facts.library_fetched_at_ms.value,
                                 records: Int(facts.library_records))
        report.tier = facts.tier.value.map(UsersBridge.tier(of:))
        return report
    }

    /// The model library knowledge of the core's.
    ///
    /// - Parameters:
    ///   - state: What the core knows of the library.
    ///   - fetched: When it was fetched, in milliseconds since 1970.
    ///   - records: How many records it held.
    /// - Returns: The model value.
    static func library(
        of state: libchiaking.catalog.LibraryState?,
        at fetched: Int64?,
        records: Int
    ) -> CatalogFetchReport.Library {
        switch state {
        case nil:
            .unknown
        case .unavailable:
            .unavailable
        case .fetched, .partial:
            .fetched(CatalogBridge.date(of: fetched ?? 0), records: records)
        }
    }

    /// The model rule of the core's.
    ///
    /// - Parameter rule: The core's rule.
    /// - Returns: The model value.
    static func rule(of rule: libchiaking.catalog.Explanation.Rule) -> CatalogRule {
        switch rule {
        case .listed_by_service:
            .listedInCatalog
        case .platform:
            .platform
        case .service:
            .service
        case .included_with_plus:
            .includedWithPlus
        case .tier:
            .tier
        case .counts_as_game:
            .countsAsGame
        case .library_match:
            .libraryMatch
        case .merged_into_listing:
            .mergedIntoListing
        case .own_listing:
            .ownListing
        case .owned_duplicate:
            .ownedDuplicate
        case .trial_superseded:
            .trialSuperseded
        case .disc_upgrade:
            .discUpgrade
        case .ownership:
            .ownership
        case .ps5_native:
            .ps5Native
        case .duplicate_launch:
            .duplicateLaunch
        case .already_owned:
            .alreadyOwned
        case .list_streamability:
            .listStreamability
        case .storefront:
            .storefront
        case .remembered_refusal:
            .rememberedRefusal
        case .release:
            .release
        case .same_product:
            .sameProduct
        case .access_route:
            .accessRoute
        case .premium_branding:
            .premiumBranding
        case .premium_entitlement:
            .premiumEntitlement
        case .joined_by_entitlement:
            .joinedByEntitlement
        case .joined_by_product:
            .joinedByProduct
        case .bundle_ownership:
            .bundleOwnership
        }
    }

    /// The model step outcome of the core's.
    ///
    /// - Parameter outcome: The core's outcome.
    /// - Returns: The model value.
    static func outcome(of outcome: libchiaking.catalog.Explanation.Outcome) -> CatalogStepOutcome {
        switch outcome {
        case .passed:
            .passed
        case .failed:
            .failed
        case .noted:
            .noted
        case .unchecked:
            .unchecked
        }
    }
}

/// Reads the titles the core's catalog reports into model cloud games.
enum CloudGameReader {
    /// The model title of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The title.
    static func game(of facts: chiaki_bridge.GameFacts) -> CloudGame {
        CloudGame(
            productId: String(facts.product_id),
            name: String(facts.name),
            imageUrl: CatalogBridge.text(String(facts.cover_url)),
            landscapeImageUrl: CatalogBridge.text(String(facts.landscape_cover_url)),
            platform: platform(of: facts.platform),
            isOwned: facts.ownership == .owned,
            plusCatalog: facts.included,
            streamServiceType: facts.service == .ps5_cloud
                ? "pscloud"
                : "psnow",
            conceptUrl: facts.concept_url.value.map { String($0) },
            conceptId: facts.concept_id.value.map { String($0) },
            visible: facts.visible,
            hideReason: facts.hide_reason.value.map(hideReason(of:)),
            standing: standing(of: facts.standing),
            launchRefusal: facts.launch_refusal.value.map(TitleChecksBridge.refusal(of:)),
            needsLibraryAdd: facts.needs_library_add,
            canBeAddedToLibrary: facts.can_be_added_to_library,
            needsStorefrontCheck: facts.needs_storefront_check,
            release: release(of: facts.release, at: facts.release_ms.value),
            ownershipId: facts.ownership_id.value.map { String($0) },
            isTrial: facts.is_trial,
            trialEnded: facts.trial_ended,
            isPlayFirstTrial: facts.is_play_first_trial,
            trialOffer: trialOffer(of: facts.trial_offer),
            bundle: facts.is_bundle
                ? CloudBundle(isOwned: facts.bundle_owned, games: facts.children.compactMap(bundled(of:)))
                : nil,
            otherVersion: facts.other_version_product_id.value.map {
                CloudOtherVersion(productId: String($0), leads: facts.leads_versions)
            }
        )
    }

    /// The model bundled game of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The game, or `nil` when it has no product id.
    static func bundled(of facts: chiaki_bridge.BundledGameFacts) -> CloudBundledGame? {
        guard let product = facts.product_id.value.map({ String($0) }), !product.isEmpty else {
            return nil
        }
        return CloudBundledGame(
            productId: product,
            entitlementId: String(facts.entitlement_id),
            isOwned: facts.owned,
            launchRefusal: facts.launch_refusal.value.map(TitleChecksBridge.refusal(of:))
        )
    }

    /// The model release date of the core's.
    ///
    /// - Parameters:
    ///   - kind: How the title is released.
    ///   - milliseconds: The release time, in milliseconds since 1970.
    /// - Returns: The model value.
    static func release(of kind: chiaki_bridge.ReleaseKind, at milliseconds: Int64?) -> CloudReleaseDate {
        switch kind {
        case .unrestricted:
            .unrestricted
        case .unannounced:
            .unannounced
        case .scheduled:
            milliseconds.map { .scheduled(CatalogBridge.date(of: $0)) } ?? .unannounced
        }
    }

    /// The platform label of the core's platform.
    ///
    /// - Parameter platform: The core's platform.
    /// - Returns: The label.
    static func platform(of platform: libchiaking.catalog.Platform) -> String {
        switch platform {
        case .ps3:
            "PS3"
        case .ps4:
            "PS4"
        case .ps5:
            "PS5"
        }
    }

    /// The hide reason the library logs for the core's.
    ///
    /// - Parameter reason: The core's reason.
    /// - Returns: The reason's name.
    static func hideReason(of reason: libchiaking.catalog.HideReason) -> String {
        switch reason {
        case .not_in_service:
            "not_in_service"
        case .not_ps5_native:
            "not_ps5_native"
        case .duplicate_launch:
            "duplicate_launch"
        case .already_owned:
            "already_owned"
        case .tier_does_not_include:
            "tier_does_not_include"
        case .copy_does_not_stream:
            "copy_does_not_stream"
        }
    }

    /// The model trial offer of the core's.
    ///
    /// - Parameter offer: The core's trial offer.
    /// - Returns: The model value, or `nil` when no trial version is offered.
    static func trialOffer(of offer: libchiaking.catalog.TrialOffer) -> CloudTrialOffer? {
        switch offer {
        case .none:
            nil
        case .demo:
            .demo
        case .play_first_trial:
            .playFirstTrial
        }
    }

    /// The model standing of the core's.
    ///
    /// - Parameter standing: The core's standing.
    /// - Returns: The model value.
    static func standing(of standing: libchiaking.catalog.Standing) -> CloudStanding {
        switch standing {
        case .may_stream:
            .mayStream
        case .in_library:
            .inLibrary
        case .included:
            .included
        case .store:
            .store
        case .ownership_unknown:
            .ownershipUnknown
        }
    }
}
