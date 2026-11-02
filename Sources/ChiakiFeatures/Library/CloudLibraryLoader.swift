import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Loads the cloud library of the selected account: the catalog, the recently played history and the store
/// page checks of the games opened.
///
/// Changing the account starts over with an empty library; every answer carries the account and the load that
/// asked for it, so an answer for an earlier load is ignored. While the catalog loads, the loading phase holds
/// the latest state the core reported for its fetch, tagged the same way. A state that ends a core attempt does not
/// end the load: a refresh may follow a running attempt into a fresh one, so only the catalog's own answer moves the
/// library to the catalog or the error view. The tab moves to Recently played once history arrives, unless the
/// person picked a tab.
///
/// Releases are judged at the server's time when a reply has supplied it, else the device's. Once a catalog is
/// loaded the loader waits for its next scheduled release; when it passes, the title leaves Pre-orders for
/// its own tab and the catalog reloads, so the server's answer replaces the guess. The wait stops with the library
/// and is caught up when the library is shown again for the same account.
struct CloudLibraryLoader: Reducer {
    /// The cloud library's state.
    typealias State = CloudLibraryFeature.State

    /// What the cloud library can do.
    typealias Action = CloudLibraryFeature.Action

    @Dependency(\.catalog) private var catalog
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.locale) private var locale
    @Dependency(\.settings) private var settings
    @Dependency(\.uuid) private var uuid

    /// Reacts to the account, the load's answers and the store page checks.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .account(let account):
                return changeAccount(&state, to: account)
            case .refresh:
                return refresh(&state)
            case let .libraryRefreshCooldownRead(attempt, cooldown):
                return coolDown(&state, attempt: attempt, for: cooldown)
            case .libraryRefreshCooled(let attempt):
                guard case .coolingDown(attempt, _) = state.libraryRefresh else {
                    return .none
                }
                state.libraryRefresh = .ready
                return .none
            case .loaded(let account, let attempt, let snapshot):
                return loaded(&state, account: account, attempt: attempt, snapshot: snapshot)
            case .recentlyPlayed(let account, let attempt, let played):
                guard state.accountID == account, state.recentAttempt == attempt else {
                    return .none
                }
                state.listing.recentlyPlayed = played
                if case .loading = state.phase {
                    return .none
                }
                Self.settleFilter(&state, choosing: false)
                return .none
            case .failed(let account, let attempt, let failure):
                guard state.accountID == account, state.phase.loadingAttempt == attempt else {
                    return .none
                }
                state.phase = .failed(failure)
                guard case .coolingDown(attempt, _) = state.libraryRefresh else {
                    return .none
                }
                state.libraryRefresh = .ready
                return .cancel(id: CloudLibraryCancelID.libraryCooldown)
            case .fetchState(let account, let attempt, let fetch):
                return observed(&state, account: account, attempt: attempt, fetch: fetch)
            case .releaseDue(let account, let attempt):
                guard state.accountID == account, state.recentAttempt == attempt, state.phase == .ready else {
                    return .none
                }
                return catchUpReleases(&state)
            case .stop:
                if state.phase != .ready {
                    state.phase = .idle
                }
                state.cardChecks = state.cardChecks.filter { $0.value != .checking }
                state.noteConfirmed()
                return .merge(
                    .cancel(id: CloudLibraryCancelID.load),
                    .cancel(id: CloudLibraryCancelID.unlock),
                    .cancel(id: CloudLibraryCancelID.cardChecks),
                    CloudLibraryLauncher.stopLaunchChecks(&state)
                )
            case let .cardChecked(account, id, check):
                guard state.accountID == account else {
                    return .none
                }
                state.note(check, for: id)
                Self.settleFilter(&state, choosing: false)
                return .none
            case let .trialChecked(account, id, offered):
                guard state.accountID == account else {
                    return .none
                }
                if offered {
                    state.listing.trialsWithdrawn.remove(id)
                } else if state.listing.game(id)?.trialOffer == .playFirstTrial {
                    state.listing.trialsWithdrawn.insert(id)
                }
                return .none
            default:
                return .none
            }
        }
    }

    /// Asks the store page whether a game opened in the detail streams, unless that is known or asked already.
    ///
    /// - Parameters:
    ///   - state: The cloud library's state.
    ///   - game: The game.
    /// - Returns: The effect that runs the check.
    func runCardCheck(_ state: inout State, game: CloudGame) -> Effect<Action> {
        guard CloudCardCheck.needed(for: game), let account = state.accountID,
              state.cardChecks[game.id] != .checking, state.cardChecks[game.id]?.isSettled != true else {
            return .none
        }
        state.note(.checking, for: game.id)
        return .run { [catalog] send in
            let check = await catalog.storefrontCheck(account, game)
            await send(.cardChecked(account, game.id, check.card))
            if let offered = check.offersTrial {
                await send(.trialChecked(account, game.id, offered))
            }
        }
        .cancellable(id: CloudLibraryCancelID.cardChecks)
    }

    /// Judges releases again at the current time after the library rewrote a game or was shown again,
    /// settling the tab and waiting for the next release.
    ///
    /// - Parameter state: The cloud library's state.
    /// - Returns: A reload when a real title unlocked, else the wait for the next release.
    func catchUpReleases(_ state: inout State) -> Effect<Action> {
        guard let account = state.accountID, let attempt = state.recentAttempt, state.phase == .ready else {
            return .none
        }
        let before = state.listing.now
        state.listing.now = trustedNow
        let unlocked = state.listing.listed.filter { game in
            game.release.unlock(after: before) != nil && !game.release.awaitsRelease(at: state.listing.now)
        }
        Self.settleFilter(&state, choosing: false)
        guard unlocked.contains(where: { !CloudSamplePreorders.isSample($0) }) else {
            return waitForUnlock(state, account: account, attempt: attempt)
        }
        return load(&state, force: true)
    }

    private func changeAccount(_ state: inout State, to account: UUID?) -> Effect<Action> {
        guard state.accountID != account || state.phase == .idle else {
            let caughtUp = catchUpReleases(&state)
            guard let game = state.selectedGame else {
                return caughtUp
            }
            return .merge(caughtUp, runCardCheck(&state, game: game))
        }
        let cardChecks = state.cardChecks
        let shape = state.gridShape
        state = State()
        state.gridShape = shape
        state.listing.resize(to: shape.size, keeping: nil)
        state.cardChecks = cardChecks.filter { $0.value != .checking }
        state.noteConfirmed()
        state.accountID = account
        let stopped = Effect<Action>.merge(
            .cancel(id: CloudLibraryCancelID.title),
            .cancel(id: CloudLibraryCancelID.cooldown),
            .cancel(id: CloudLibraryCancelID.libraryCooldown),
            .cancel(id: CloudLibraryCancelID.launchChecks),
            .cancel(id: CloudLibraryCancelID.cardChecks)
        )
        guard account != nil else {
            return .merge(
                .cancel(id: CloudLibraryCancelID.load),
                .cancel(id: CloudLibraryCancelID.unlock),
                stopped
            )
        }
        return .merge(stopped, load(&state, force: false))
    }

    private func refresh(_ state: inout State) -> Effect<Action> {
        guard state.libraryRefresh.isReady else {
            return .none
        }
        let loading = load(&state, force: true)
        guard let attempt = state.phase.loadingAttempt else {
            return loading
        }
        state.libraryRefresh = .coolingDown(attempt, until: nil)
        return .merge(
            loading,
            .run { [settings] send in
                let developer = (try? await settings.load(DeveloperSettings.self)) ?? DeveloperSettings()
                await send(.libraryRefreshCooldownRead(attempt, developer.libraryRefreshCooldown))
            }
        )
    }

    private func coolDown(_ state: inout State, attempt: UUID, for cooldown: Duration) -> Effect<Action> {
        guard case .coolingDown(attempt, nil) = state.libraryRefresh else {
            return .none
        }
        guard cooldown > .zero else {
            state.libraryRefresh = .ready
            return .none
        }
        state.libraryRefresh = .coolingDown(
            attempt,
            until: date.now.addingTimeInterval(TimeInterval(cooldown.components.seconds))
        )
        return .run { [clock] send in
            try await clock.sleep(for: cooldown)
            await send(.libraryRefreshCooled(attempt))
        }
        .cancellable(id: CloudLibraryCancelID.libraryCooldown, cancelInFlight: true)
    }

    private func load(_ state: inout State, force: Bool) -> Effect<Action> {
        guard let account = state.accountID else {
            return .none
        }
        let attempt = uuid()
        state.phase = .loading(attempt, fetch: nil)
        state.recentAttempt = attempt
        let locale = locale.identifier.replacingOccurrences(of: "_", with: "-")
        return .run { [catalog, clock] send in
            let (states, observed) = AsyncStream.makeStream(of: CloudLibraryFetchState.self)
            async let forwarded: Void = Self.forward(states, account: account, attempt: attempt, send: send)
            await withTaskGroup(of: CloudLibraryLoad.Arrival.self) { group in
                group.addTask {
                    .history((try? await catalog.recentlyPlayed(account)) ?? [])
                }
                group.addTask {
                    defer {
                        observed.finish()
                    }
                    do {
                        return try await .library(.success(catalog.library(account, force, locale) { fetch in
                            observed.yield(fetch)
                        }))
                    } catch is CancellationError where Task.isCancelled {
                        return .cancelled
                    } catch {
                        return .library(.failure(error as? CloudLibraryFailure ?? .network))
                    }
                }
                var arrivals = CloudLibraryLoad()
                while let arrival = await group.next() {
                    switch arrivals.receive(arrival) {
                    case .wait:
                        continue
                    case .waitForHistory:
                        group.addTask {
                            try? await clock.sleep(for: CloudLibraryFeature.historyWait)
                            return .historyDeadline
                        }
                    case .send(let events):
                        for event in events {
                            await send(Self.action(for: event, account: account, attempt: attempt))
                        }
                    case .finish(let events):
                        group.cancelAll()
                        for event in events {
                            await send(Self.action(for: event, account: account, attempt: attempt))
                        }
                        return
                    }
                }
            }
            observed.finish()
            await forwarded
        }
        .cancellable(id: CloudLibraryCancelID.load, cancelInFlight: true)
    }

    private static func forward(
        _ states: AsyncStream<CloudLibraryFetchState>,
        account: UUID,
        attempt: UUID,
        send: Send<Action>
    ) async {
        for await fetch in states {
            await send(.fetchState(account, attempt, fetch))
        }
    }

    private func observed(
        _ state: inout State, account: UUID, attempt: UUID, fetch: CloudLibraryFetchState
    ) -> Effect<Action> {
        guard state.accountID == account, state.phase.loadingAttempt == attempt else {
            return .none
        }
        state.phase = .loading(attempt, fetch: fetch)
        return .none
    }

    private static func action(for event: CloudLibraryLoad.Event, account: UUID, attempt: UUID) -> Action {
        switch event {
        case .history(let played):
            .recentlyPlayed(account, attempt, played)
        case .loaded(let snapshot):
            .loaded(account, attempt, snapshot)
        case .failed(let failure):
            .failed(account, attempt, failure)
        }
    }

    private func loaded(
        _ state: inout State, account: UUID, attempt: UUID, snapshot: CloudLibrarySnapshot
    ) -> Effect<Action> {
        guard state.accountID == account, state.phase.loadingAttempt == attempt else {
            return .none
        }
        state.listing.now = trustedNow
        state.snapshot = snapshot
        state.phase = .ready
        state.recentAttempt = attempt
        if state.selection != nil, state.selectedGame == nil {
            state.closeDetail()
        }
        Self.settleFilter(&state, choosing: true)
        return waitForUnlock(state, account: account, attempt: attempt)
    }

    private var trustedNow: Date {
        catalog.serverTime() ?? date.now
    }

    private func waitForUnlock(_ state: State, account: UUID, attempt: UUID) -> Effect<Action> {
        guard let unlock = state.listing.nextUnlock else {
            return .cancel(id: CloudLibraryCancelID.unlock)
        }
        let wait = Duration.seconds(max(0, unlock.timeIntervalSince(state.listing.now)))
            + CloudLibraryFeature.unlockMargin
        return .run { [clock] send in
            try await clock.sleep(for: wait)
            await send(.releaseDue(account, attempt))
        }
        .cancellable(id: CloudLibraryCancelID.unlock, cancelInFlight: true)
    }

    /// Moves off a tab that has nothing left to show, and onto Recently played when the library chooses the
    /// tab and there is history.
    ///
    /// - Parameters:
    ///   - state: The cloud library's state.
    ///   - choosing: Whether the library may pick Recently played on its own.
    static func settleFilter(_ state: inout State, choosing: Bool) {
        if state.filter == .recent, !state.listing.hasRecentlyPlayed {
            state.filter = .all
            state.show(page: 0)
        } else if state.filter == .preorders, !state.listing.hasPreorders {
            state.filter = .all
            state.show(page: 0)
        } else if choosing, state.filterChoice == .automatic, state.listing.hasRecentlyPlayed,
                  state.filter != .recent {
            state.filter = .recent
            state.show(page: 0)
        }
    }
}

/// Orders what one cloud library load reports: the catalog, the recently played history and their failures.
///
/// The catalog and the history are fetched together. History that arrives before the catalog, or within
/// ``CloudLibraryFeature/historyWait`` after it, is reported first so the library can open on Recently played;
/// later history is reported after the catalog. The load runs its fetches as child tasks of one task group,
/// so cancelling the load cancels both fetches and the wait at once.
public struct CloudLibraryLoad {
    /// One completion delivered to the load by a child task.
    public enum Arrival: Sendable {
        /// The recently played history arrived; a failed fetch arrives as an empty history.
        case history([CloudRecentlyPlayed])
        /// The catalog fetch finished.
        case library(Result<CloudLibrarySnapshot, CloudLibraryFailure>)
        /// The catalog fetch stopped because the load was cancelled.
        case cancelled
        /// The wait for history after the catalog arrived ran out.
        case historyDeadline
    }

    /// One result the load reports to the reducer.
    public enum Event: Equatable, Sendable {
        /// The recently played history to show.
        case history([CloudRecentlyPlayed])
        /// The catalog to show.
        case loaded(CloudLibrarySnapshot)
        /// Why the catalog could not be loaded.
        case failed(CloudLibraryFailure)
    }

    /// What the load does after one arrival.
    public enum Step: Equatable, Sendable {
        /// Keep waiting for the next arrival.
        case wait
        /// Start the wait for history, then keep waiting.
        case waitForHistory
        /// Report these events and keep waiting.
        case send([Event])
        /// Report these events and stop every remaining child task.
        case finish([Event])
    }

    private enum Phase {
        case fetching(history: [CloudRecentlyPlayed]?)
        case awaitingHistory(CloudLibrarySnapshot)
        case awaitingLateHistory
        case finished
    }

    private var phase = Phase.fetching(history: nil)

    /// Moves the load on by one arrival.
    ///
    /// - Parameter arrival: The completion a child task delivered.
    /// - Returns: What the load does next.
    public mutating func receive(_ arrival: Arrival) -> Step {
        switch (phase, arrival) {
        case (.finished, _):
            return .wait
        case (_, .cancelled):
            phase = .finished
            return .finish([])
        case (.fetching, .history(let played)):
            phase = .fetching(history: played)
            return .wait
        case (.fetching(let history), .library(.success(let snapshot))):
            guard let history else {
                phase = .awaitingHistory(snapshot)
                return .waitForHistory
            }
            phase = .finished
            return .finish([.history(history), .loaded(snapshot)])
        case (_, .library(.failure(let failure))):
            phase = .finished
            return .finish([.failed(failure)])
        case (.awaitingHistory(let snapshot), .history(let played)):
            phase = .finished
            return .finish([.history(played), .loaded(snapshot)])
        case (.awaitingHistory(let snapshot), .historyDeadline):
            phase = .awaitingLateHistory
            return .send([.loaded(snapshot)])
        case (.awaitingLateHistory, .history(let played)):
            phase = .finished
            return .finish([.history(played)])
        case (.fetching, .historyDeadline), (.awaitingHistory, .library(.success)),
             (.awaitingLateHistory, .library(.success)), (.awaitingLateHistory, .historyDeadline):
            return .wait
        }
    }
}

/// Runs the launch checks of the game the detail shows and hands a cleared launch to the library's parent.
///
/// Only the latest checks are followed. A game that the PlayStation website list marks as not streaming, but whose
/// store page says it does, is played only after the website warning is answered with Play.
struct CloudLibraryLauncher: Reducer {
    /// The cloud library's state.
    typealias State = CloudLibraryFeature.State

    /// What the cloud library can do.
    typealias Action = CloudLibraryFeature.Action

    @Dependency(\.catalog) private var catalog
    @Dependency(\.uuid) private var uuid

    /// Reacts to the play buttons, the bundle picker, the launch checks and the website warning.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .checkAndPlay(let request):
                return checkAndPlay(&state, request: request)
            case .openBundlePicker(let id):
                guard state.selection == id, state.selectedGame?.opensBundlePicker == true else {
                    return .none
                }
                state.bundlePicker = id
                return .none
            case .playBundleGame(let id):
                return playBundleGame(&state, choice: id)
            case .launchChecked(let attempt, let event):
                return launchChecked(&state, attempt: attempt, event: event)
            case .websiteWarning(.presented(.play)):
                guard let request = state.launchChecks?.handOff else {
                    return .none
                }
                state.launchChecks?.launched()
                return .send(.delegate(.play(request)))
            case .websiteWarning(.dismiss):
                return Self.stopLaunchChecks(&state)
            default:
                return .none
            }
        }
    }

    /// Stops the running launch checks and withdraws the website warning.
    ///
    /// - Parameter state: The cloud library's state.
    /// - Returns: The effect that cancels the checks.
    static func stopLaunchChecks(_ state: inout State) -> Effect<Action> {
        state.launchChecks = nil
        state.websiteWarning = nil
        return .cancel(id: CloudLibraryCancelID.launchChecks)
    }

    private func checkAndPlay(
        _ state: inout State, request: CloudLaunchRequest, shownOn card: String? = nil
    ) -> Effect<Action> {
        let card = card ?? request.game.id
        guard state.launchChecks?.isRunning != true || state.launchChecks?.gameID != card else {
            return .none
        }
        guard let product = request.game.product else {
            return .none
        }
        let attempt = uuid()
        state.launchChecks = CloudLaunchChecks(request: request.uncleared, attempt: attempt, shownOn: card)
        let account = request.accountID
        return .run { [catalog] send in
            for await event in catalog.clearForLaunch(account, product) {
                await send(.launchChecked(attempt, event))
            }
        }
        .cancellable(id: CloudLibraryCancelID.launchChecks, cancelInFlight: true)
    }

    private func launchChecked(
        _ state: inout State, attempt: UUID, event: CloudLaunchClearanceEvent
    ) -> Effect<Action> {
        guard state.launchChecks?.attempt == attempt else {
            return .none
        }
        switch event {
        case .check(let check):
            state.launchChecks?.observe(check)
            return .none
        case .finished(.failure(let failure)) where failure.reason == .cancelled:
            state.launchChecks = nil
            return .none
        case .finished(let result):
            state.launchChecks?.finish(result)
            return handOff(&state)
        }
    }

    private func handOff(_ state: inout State) -> Effect<Action> {
        guard let checks = state.launchChecks, let request = checks.handOff,
              let game = state.listing.game(checks.gameID) else {
            return .none
        }
        if game.standing(after: state.cardChecks[game.id]) == .mayStream {
            state.websiteWarning = Self.websiteWarning
            return .none
        }
        state.launchChecks?.launched()
        return .send(.delegate(.play(request)))
    }

    private static let websiteWarning = AlertState<Action.WebsiteWarning> {
        TextState("Playability comes from the store page")
    } actions: {
        ButtonState(action: .play) {
            TextState("Play")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState(
            "The PlayStation website list marks this game as not supporting cloud streaming. "
                + "The store page for this edition says it does, so Play follows the store page."
        )
    }

    private func playBundleGame(_ state: inout State, choice id: String) -> Effect<Action> {
        guard let bundle = state.bundlePicker, let accountID = state.accountID,
              let choice = state.bundleChoices.first(where: { $0.id == id }), choice.refusal == nil,
              let request = try? CloudLaunchRequest(accountID: accountID, game: choice.game) else {
            return .none
        }
        return checkAndPlay(&state, request: request, shownOn: bundle)
    }
}
