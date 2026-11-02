import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Lists the titles installed on an account's consoles and starts one, through the open core.
///
/// Both talk to PSN and block a core thread, so they run on a dispatch queue while the calling task waits;
/// cancelling the task cancels the core request.
public struct ConsoleTitlesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The recently played titles of every console on the account.
    ///
    /// - Parameter account: The account.
    /// - Returns: One entry per console the core knows.
    /// - Throws: The `ChiakiModels/ConsoleTitlesFailure` that stopped the listing.
    public func recentlyPlayed(account: AccountID) async throws(ConsoleTitlesFailure) -> [ConsoleTitles] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.ConsoleTitlesBridge.recently_played(
                request,
                UsersBridge.vector(account)
            ))
        }
        return try result.get()
    }

    /// Starts a title on a console.
    ///
    /// - Parameters:
    ///   - titleID: The title id.
    ///   - launchID: The id the console starts it with.
    ///   - console: The console.
    ///   - account: The account that starts it.
    /// - Returns: How far the console got.
    /// - Throws: The `ChiakiModels/ConsoleTitlesFailure` that stopped the start.
    public func start(
        titleID: String,
        launchID: String,
        on console: HardwareID,
        as account: AccountID
    ) async throws(ConsoleTitlesFailure) -> ConsoleLaunchState {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.ConsoleTitlesBridge.start_title(
                request, UsersBridge.vector(account), chiaki_bridge.Bytes(console.bytes),
                std.string(titleID), std.string(launchID), nil, nil
            ))
        }
        return try result.get()
    }

    /// The model result of a recently played listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The consoles' titles or the failure.
    static func result(of outcome: chiaki_bridge
        .RecentlyPlayedOutcome) -> Result<[ConsoleTitles], ConsoleTitlesFailure> {
        switch outcome.kind() {
        case .listed:
            return .success(outcome.shelves().compactMap { shelf in
                HardwareID(bytes: Array(shelf.hardware_id)).map {
                    ConsoleTitles(hardwareID: $0, titles: shelf.titles.map(title(of:)))
                }
            })
        case .unanswered:
            return .failure(failure(of: outcome.why_unanswered().reason))
        case .refused:
            return .failure(failure(of: outcome.refusal()))
        }
    }

    /// The model result of a title start.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: How far the console got, or the failure.
    static func result(of outcome: chiaki_bridge
        .StartOutcome) -> Result<ConsoleLaunchState, ConsoleTitlesFailure> {
        switch outcome.kind() {
        case .started:
            return .success(state(of: outcome.state()))
        case .unavailable:
            return .failure(outcome.why_unavailable().unanswered.value
                .map { failure(of: $0.reason) } ?? .unavailable)
        case .failed:
            let failed = outcome.failure()
            switch failed.reason {
            case .timed_out:
                return .success(state(of: failed.reached))
            case .cancelled:
                return .failure(.cancelled)
            case .refused:
                return .failure(.rejected)
            case .unanswered:
                return .failure(failed.unanswered.value.map { Self.failure(of: $0.reason) } ?? .unavailable)
            case .ps5_only, .not_paired, .not_on_account, .forgotten, .not_available:
                return .failure(.unavailable)
            }
        case .refused:
            return .failure(failure(of: outcome.refusal()))
        }
    }

    /// The model title of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The title.
    static func title(of facts: chiaki_bridge.InstalledTitleFacts) -> RecentTitle {
        RecentTitle(
            titleID: String(facts.title_id),
            launchID: String(facts.start_id),
            name: String(facts.name),
            imageURL: String(facts.cover_url),
            platform: facts.platform == .ps5
                ? "PS5"
                : "PS4",
            lastPlayedMs: facts.last_used_ms.value ?? 0,
            recent: facts.recently_played,
            conceptID: String(facts.concept_id),
            lastPlayedKnown: facts.last_use_known.value.map(known(of:)) ?? .onThisConsole
        )
    }

    /// The model last-played knowledge of the core's.
    ///
    /// - Parameter known: How the core learned the time.
    /// - Returns: The model value.
    static func known(
        of known: libchiaking.consoles.InstalledTitle.LastUse.Known
    ) -> RecentTitle.LastPlayedKnown {
        switch known {
        case .on_this_console:
            .onThisConsole
        case .on_the_account:
            .onTheAccount
        }
    }

    /// The model launch state of a core start state.
    ///
    /// - Parameter state: The core's state.
    /// - Returns: The model state.
    static func state(of state: libchiaking.consoles.StartState) -> ConsoleLaunchState {
        switch state {
        case .pending:
            .pending
        case .starting:
            .starting
        case .completed:
            .completed
        case .failed:
            .failed
        }
    }

    /// The model failure of a request PSN did not answer.
    ///
    /// - Parameter reason: Why PSN did not answer.
    /// - Returns: The failure.
    static func failure(of reason: libchiaking.users.Unanswered.Reason) -> ConsoleTitlesFailure {
        switch reason {
        case .cancelled:
            .cancelled
        case .signed_out:
            .signedOut
        case .sign_in_expired, .store_access_lapsed, .remote_play_access_missing:
            .auth
        case .rejected:
            .rejected
        case .rate_limited, .unavailable, .malformed, .old_service_refused:
            .unavailable
        }
    }

    /// The model failure of a refusal the bridge made before the core ran.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The failure.
    static func failure(of refusal: chiaki_bridge.ConsolesRefusal) -> ConsoleTitlesFailure {
        switch refusal {
        case .invalid_title:
            .rejected
        case .core_closed, .unknown_user, .unknown_console, .invalid_address, .address_not_for_generation,
             .store_unavailable:
            .unavailable
        }
    }
}
