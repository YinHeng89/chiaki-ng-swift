import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Asks the store and the catalog about single titles through the open core: whether they stream, whether
/// they may be launched, their store pages, detail pages and images.
///
/// Each request blocks a core thread, so it runs on a dispatch queue while the calling task waits; cancelling
/// the task cancels the core request.
public struct TitleChecksBridge: Sendable {
    private final class LaunchObserver: @unchecked Sendable {
        let observe: @Sendable (CloudLaunchCheck) -> Void

        init(_ observe: @escaping @Sendable (CloudLaunchCheck) -> Void) {
            self.observe = observe
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// What the storefront says about streaming one title.
    ///
    /// - Parameters:
    ///   - account: The account that asks.
    ///   - productID: The title's product id.
    /// - Returns: The storefront's answer, or why there was none.
    public func storefront(account: AccountID,
                           productID: String) async -> Result<StorefrontCheck, CatalogUnanswered> {
        await CoreCancellation.run { request in
            Self.result(of: chiaki_bridge.TitleChecksBridge.storefront(
                request,
                UsersBridge.vector(account),
                std.string(productID)
            ))
        }
    }

    /// Runs every check before a cloud title is launched, reporting each step as it starts.
    ///
    /// - Parameters:
    ///   - account: The account that launches.
    ///   - productID: The title's product id.
    ///   - observe: Called with each check as it starts, on a core thread.
    /// - Returns: Whether the title may be launched, or why the checks could not finish.
    public func clearForLaunch(
        account: AccountID,
        productID: String,
        observe: @escaping @Sendable (CloudLaunchCheck) -> Void
    ) async -> Result<CloudLaunchClearance, CatalogUnanswered> {
        let observer = LaunchObserver(observe)
        return await CoreCancellation.run { request in
            withExtendedLifetime(observer) {
                Self.result(of: chiaki_bridge.TitleChecksBridge.clear_for_launch(
                    request,
                    UsersBridge.vector(account),
                    std.string(productID),
                    { check, context in
                        guard let context else {
                            return
                        }
                        Unmanaged<LaunchObserver>.fromOpaque(context).takeUnretainedValue()
                            .observe(TitleChecksBridge.check(of: check))
                    },
                    Unmanaged.passUnretained(observer).toOpaque()
                ))
            }
        }
    }

    /// The store page of one title.
    ///
    /// - Parameters:
    ///   - account: The account that asks.
    ///   - productID: The title's product id.
    /// - Returns: The page, or `nil` when the store did not give one.
    public func storePage(account: AccountID, productID: String) async -> URL? {
        let page = await CoreCancellation.run { request in
            let outcome = chiaki_bridge.TitleChecksBridge.store_page(
                request,
                UsersBridge.vector(account),
                std.string(productID)
            )
            return outcome.kind() == .answered
                ? String(outcome.url())
                : nil
        }
        return page.flatMap(URL.init(string:))
    }

    /// The detail page of one title.
    ///
    /// - Parameters:
    ///   - account: The account that asks.
    ///   - productID: The title's product id.
    /// - Returns: The details, or why there were none.
    public func details(account: AccountID,
                        productID: String) async -> Result<GameDetails, CatalogUnanswered> {
        await CoreCancellation.run { request in
            Self.result(of: chiaki_bridge.TitleChecksBridge.details(
                request,
                UsersBridge.vector(account),
                std.string(productID)
            ))
        }
    }

    /// The detail page of the titles grouped under one concept.
    ///
    /// - Parameters:
    ///   - account: The account that asks.
    ///   - conceptID: The concept id.
    /// - Returns: The details, or why there were none.
    public func details(account: AccountID,
                        conceptID: String) async -> Result<GameDetails, CatalogUnanswered> {
        await CoreCancellation.run { request in
            Self.result(of: chiaki_bridge.TitleChecksBridge.details_by_concept(
                request,
                UsersBridge.vector(account),
                std.string(conceptID)
            ))
        }
    }

    /// One catalog image, from the core's cache or the network.
    ///
    /// - Parameters:
    ///   - url: The image's address.
    ///   - calls: The limiter the fetch waits on.
    /// - Returns: The image's bytes, or why there were none.
    public func image(url: String, through calls: CoreImageCalls) async -> Result<Data, CatalogUnanswered> {
        do {
            return try await calls.run {
                await CoreCancellation.run(qos: .utility) { request in
                    Self.result(of: chiaki_bridge.TitleChecksBridge.image(request, std.string(url)))
                }
            }
        } catch {
            return .failure(CatalogUnanswered(reason: .cancelled))
        }
    }

    /// The model result of a storefront check.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The answer or the failure.
    static func result(of outcome: chiaki_bridge
        .StorefrontOutcome) -> Result<StorefrontCheck, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            let answer = outcome.storefront()
            return .success(StorefrontCheck(
                streaming: streaming(of: answer.streaming),
                ownedPerStore: answer.owned_per_store,
                offersLibraryAdd: answer.offers_library_add,
                notice: String(answer.notice),
                offersTrial: answer.offers_trial.value
            ))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of the launch checks, taking ownership of any cleared launch.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The clearance or the failure.
    static func result(
        of outcome: chiaki_bridge.ClearanceOutcome
    ) -> Result<CloudLaunchClearance, CatalogUnanswered> {
        switch outcome.kind() {
        case .cleared:
            return .success(.cleared(outcome.__clearanceUnsafe().launch.map(CloudClearedLaunch.init)))
        case .declined:
            let decline = outcome.decline()
            let cause = decline.cause.value.map { CatalogUnanswered.of($0) }
            if let cause, cause.reason == .cancelled {
                return .failure(cause)
            }
            return .success(.refused(CloudClearanceRefusal(
                refusal: refusal(of: decline.kind),
                notice: String(decline.notice),
                time: decline.time_ms.value.map(CatalogBridge.date(of:)),
                needsSignIn: cause?.needsSignIn ?? false
            )))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a detail page request.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The details or the failure.
    static func result(of outcome: chiaki_bridge.DetailsOutcome) -> Result<GameDetails, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(GameDetailsReader.details(of: outcome.details()))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of an image request.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The bytes or the failure.
    static func result(of outcome: chiaki_bridge.ImageOutcome) -> Result<Data, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(Data(outcome.bytes()))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model streaming answer of the core's.
    ///
    /// - Parameter streaming: The core's answer.
    /// - Returns: The model value.
    static func streaming(
        of streaming: libchiaking.catalog.StorefrontAnswer.Streaming
    ) -> StorefrontCheck.Streaming {
        switch streaming {
        case .streams:
            .streams
        case .not_streamable:
            .notStreamable
        case .no_notice:
            .noNotice
        case .edition_missing:
            .editionMissing
        }
    }

    /// The model launch check of the core's.
    ///
    /// - Parameter check: The core's check.
    /// - Returns: The model value.
    static func check(of check: libchiaking.catalog.LaunchCheck) -> CloudLaunchCheck {
        switch check {
        case .loading_library:
            .loadingLibrary
        case .membership:
            .membership
        case .cloud_streaming:
            .cloudStreaming
        case .ownership:
            .ownership
        case .entitlement:
            .entitlement
        case .cloud_game:
            .cloudGame
        case .exclusions:
            .exclusions
        case .release:
            .release
        }
    }

    /// The model launch refusal of the core's.
    ///
    /// - Parameter kind: The core's refusal.
    /// - Returns: The model value.
    static func refusal(of kind: libchiaking.catalog.LaunchRefusal.Kind) -> CloudLaunchRefusal {
        switch kind {
        case .not_listed:
            .notListed
        case .hidden:
            .hidden
        case .buy_to_stream:
            .buyToStream
        case .add_to_library:
            .addToLibrary
        case .needs_premium:
            .needsPremium
        case .refused_by_service:
            .refusedByStreamService
        case .not_streamable:
            .notStreamable
        case .unannounced:
            .unannounced
        case .not_released:
            .notReleased
        case .no_trusted_clock:
            .noTrustedClock
        case .check_unavailable:
            .checkUnavailable
        case .invalid_title:
            .invalidTitle
        case .title_taken_down:
            .titleTakenDown
        case .streaming_unavailable:
            .streamingUnavailable
        case .purchase_needed:
            .purchaseNeeded
        case .unexpected_entitlement_state:
            .unexpectedEntitlementState
        case .choose_a_game:
            .chooseAGame
        }
    }
}

/// Reads the store details the core fetched for a title: its key art, media, ratings and facts.
enum GameDetailsReader {
    /// The model details of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The details.
    static func details(of facts: chiaki_bridge.GameDetailsFacts) -> GameDetails {
        GameDetails(
            art: art(of: facts),
            screenshots: facts.screenshot_urls.map { String($0) },
            trailers: facts.trailer_urls.compactMap { URL(string: String($0)) },
            starRating: facts.star_average.value.map { average in
                GameDetails.StarRating(
                    average: average,
                    averageText: String(facts.star_average_text),
                    ratings: Int(facts.star_ratings),
                    percentByStars: facts.star_percent.map { Int($0) }
                )
            },
            ageRating: facts.age_authority.value.map { authority in
                GameDetails.AgeRating(
                    authority: String(authority),
                    name: String(facts.age_name),
                    description: String(facts.age_description),
                    icon: facts.age_icon_url.value.map { String($0) },
                    descriptors: facts.age_descriptors.map { String($0) }
                )
            },
            publisher: String(facts.publisher),
            releasedAt: facts.released_ms.value.map(CatalogBridge.date(of:)),
            genres: facts.genres.map { String($0) }
        )
    }

    /// The model key art of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The art, or `nil` when the store offers none.
    static func art(of facts: chiaki_bridge.GameDetailsFacts) -> GameDetails.Art? {
        let logo = facts.logo_url.value.map { String($0) }
        if let background = facts.background_url.value, let hero = facts.hero_url.value, let logo {
            return .layered(GameDetails.LayeredArt(
                background: String(background),
                hero: String(hero),
                logo: logo
            ))
        }
        guard let cover = facts.game_hub_cover_url.value else {
            return nil
        }
        return .gameHub(GameDetails.GameHubArt(cover: String(cover), logo: logo))
    }
}

/// What the catalog decided about launching a cloud title.
public enum CloudLaunchClearance: Equatable, Sendable {
    /// The title may be launched, with the launch the catalog prepared when it prepared one.
    case cleared(CloudClearedLaunch?)

    /// The title may not be launched.
    case refused(CloudClearanceRefusal)
}

/// A launch the catalog cleared, held until the stream that uses it starts.
///
/// It owns the core's cleared launch and releases it when the last reference goes.
public final class CloudClearedLaunch: Equatable, @unchecked Sendable {
    /// The core's cleared launch, handed to the stream that starts the title.
    public let handle: OpaquePointer

    /// Takes ownership of a cleared launch.
    ///
    /// - Parameter handle: The core's cleared launch.
    init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        chiaki_bridge.TitleChecksBridge.release(handle)
    }

    /// Whether two references hold the same launch.
    ///
    /// - Parameters:
    ///   - lhs: One launch.
    ///   - rhs: The other.
    /// - Returns: Whether they are the same object.
    public static func == (lhs: CloudClearedLaunch, rhs: CloudClearedLaunch) -> Bool {
        lhs === rhs
    }
}
