import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Whether the Notifications panel is open.
public enum AlertsPanel: Equatable, Sendable {
    /// The panel is closed.
    case closed
    /// The panel is open.
    case open
}

/// Owns what PSN tells the selected account as it happens: game and party invitations and messages from the account's
/// push channel, the game and party invitations listed when the Notifications panel opens, the unseen count, which
/// of them raise an alert, and a home PS5 joining a party.
///
/// The watch and the listing each move through their own state machine, and every completion carries the
/// operation that started it, so an answer for an earlier account or listing never lands. Alerts pass a
/// `ChiakiModels/PSNAlertGate`, so switched-off kinds, muted senders, repeats and floods are only listed. When a
/// sender's message window ends with messages held back and the panel was not opened meanwhile, one alert
/// says how many they sent.
@Reducer public struct PSNAlertsFeature {
    /// Whether the account's push channel is watched.
    public enum Watch: Equatable, Sendable {
        /// Nothing is watched.
        case off

        /// The operation with this id watches the profile.
        case watching(ProfileID, UUID)

        /// The profile's watch ended and is not restarted until the account changes or the panel opens.
        case ended(ProfileID)

        /// The profile watched or last watched.
        public var profile: ProfileID? {
            switch self {
            case .off:
                nil
            case .watching(let profile, _), .ended(let profile):
                profile
            }
        }
    }

    /// Where the listing of invitations stands.
    public enum Listing: Equatable, Sendable {
        /// Nothing is being listed.
        case idle

        /// The operation with this id is asking PSN.
        case loading(UUID)

        /// The last listing failed.
        case failed(CloudInvitationFailure)
    }

    /// What the Notifications panel shows in place of its list.
    @Reducer public enum Destination {
        /// The account's conversations.
        case conversations(ConversationsFeature)
        /// One conversation, opened from a message.
        case conversation(ConversationFeature)
    }

    /// A PS5 of the account that can join a party, as the Notifications panel offers it.
    public struct PartyConsole: Equatable, Identifiable, Sendable {
        /// The console's hardware id.
        public let hardwareID: HardwareID

        /// The console's name.
        public let name: String

        /// The console's identity: its hardware id.
        public var id: HardwareID {
            hardwareID
        }

        /// Describes a console.
        ///
        /// - Parameters:
        ///   - hardwareID: The console's hardware id.
        ///   - name: The console's name.
        public init(hardwareID: HardwareID, name: String) {
            self.hardwareID = hardwareID
            self.name = name
        }
    }

    /// Where having a home PS5 join a party or a game session stands.
    public enum HomeJoin: Equatable, Sendable {
        /// No join has been asked for.
        case idle

        /// The operation with this id has the console join the party or game session.
        case joining(session: String, console: HardwareID, operation: UUID)

        /// The console reported that it joined the session.
        case joined(session: String, console: HardwareID)

        /// The console could not join the session.
        case failed(session: String, console: HardwareID, CloudInvitationFailure)

        /// The session the join is about, or `nil` when idle.
        public var session: String? {
            switch self {
            case .idle:
                nil
            case .joining(let session, _, _), .joined(let session, _), .failed(let session, _, _):
                session
            }
        }
    }

    /// Where clearing the list stands.
    public enum Clearing: Equatable, Sendable {
        /// Nothing is being cleared.
        case idle

        /// The operation with this id is deleting the invitations' notifications.
        case clearing(UUID)

        /// The last clear failed, so the list was read again.
        case failed(CloudInvitationFailure)
    }

    /// One entry of the Notifications panel.
    public struct Item: Equatable, Identifiable, Sendable {
        /// What the entry is.
        public enum Kind: Equatable, Sendable {
            /// A game invitation.
            case invitation(CloudGameInvitation)

            /// A party invitation.
            case party(PSNPartyAlert)

            /// A message.
            case message(PSNMessageAlert)
        }

        /// The entry's identity: the invitation's or party's session, or the message's arrival.
        public let id: String

        /// What the entry is.
        public var kind: Kind

        /// When it arrived or was sent.
        public var arrived: Date

        /// How many times the sender asked within the gate's window, counting this one; 1 for a single ask.
        public var repeats: Int

        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - id: The entry's identity.
        ///   - kind: What the entry is.
        ///   - arrived: When it arrived.
        ///   - repeats: How many times the sender asked.
        public init(id: String, kind: Kind, arrived: Date, repeats: Int = 1) {
            self.id = id
            self.kind = kind
            self.arrived = arrived
            self.repeats = repeats
        }

        /// The ids of the account's PSN notifications behind the entry, which clearing it deletes; empty for a
        /// message or a party only pushed so far.
        public var notificationIDs: [String] {
            switch kind {
            case .invitation(let invitation):
                invitation.notificationIDs
            case .party(let party):
                party.notificationIDs
            case .message:
                []
            }
        }

        /// The sender's online id, or an empty string when PSN did not say.
        public var sender: String {
            switch kind {
            case .invitation(let invitation):
                invitation.inviter
            case .party(let party):
                party.sender
            case .message(let message):
                message.sender
            }
        }

        /// Whether the entry is a game or party invitation, which share the invitation switch and window.
        public var isInvitation: Bool {
            switch kind {
            case .invitation, .party:
                true
            case .message:
                false
            }
        }

        /// The toast and system alert this entry raises.
        public var notice: CloudSystemNotice {
            let name = sender.isEmpty
                ? String(localized: .notificationsNoticeFriend)
                : sender
            switch kind {
            case .invitation(let invitation):
                return CloudSystemNotice(
                    kind: .invitation,
                    title: String(localized: .notificationsNoticeInvitedToPlay(name: name)),
                    detail: invitation.sessionName
                )
            case .party:
                return CloudSystemNotice(
                    kind: .invitation,
                    title: String(localized: .notificationsNoticeInvitedToParty(name: name))
                )
            case .message:
                return CloudSystemNotice(
                    kind: .message,
                    title: String(localized: .notificationsNoticeSentMessage(name: name))
                )
            }
        }
    }

    /// The Notifications panel's state.
    @ObservableState public struct State: Equatable {
        /// Whether the account's push channel is watched.
        public var watch = Watch.off

        /// Where the listing of invitations stands.
        public var listing = Listing.idle

        /// Where clearing the list stands.
        public var clearing = Clearing.idle

        /// Where the latest party join on a home PS5 stands.
        public var homeJoin = HomeJoin.idle

        /// The conversations or the conversation shown in place of the list.
        @Presents public var destination: Destination.State?

        /// The entries cleared or folded into a sender's repeat, which a listing does not add back.
        public var dropped: Set<String> = []

        /// The notifications of entries folded into a sender's repeat, deleted from PSN with the next clear.
        public var foldedNotificationIDs: [String] = []

        /// The entries the clear under way dropped, listed again if it fails.
        var clearingDropped: Set<String> = []

        /// How many times the watch of the account was asked to start afresh; the hosting view watches each
        /// generation for as long as it shows, so a new one replaces the running watch.
        public var generation = 0

        /// Whether macOS shows the app's alerts, once the panel has checked; `nil` before that.
        public var systemAlerts: PlatformClient.NotificationPermission?

        /// The entries, newest first.
        public var items: [Item] = []

        /// How many entries arrived while the panel was closed, since it was last opened, counting the ones
        /// held back from alerting but not those of muted senders or switched-off kinds.
        public var unseen = 0

        /// Whether the Notifications panel is open, so arriving alerts do not count as unseen.
        public var panel = AlertsPanel.closed

        /// The messages held back from each sender since their last alert, announced together when the
        /// sender's window ends unless the panel was opened.
        public var heldMessages: [String: Int] = [:]

        /// Which alerts are shown and which only listed.
        public var gate = PSNAlertGate()

        /// The stored alert settings.
        public var settings = PersistedSettingFeature<PSNAlertSettings>.State()

        /// Creates the state with nothing watched.
        public init() {}

        /// The alert settings in effect: the stored value once loaded, else the defaults.
        public var alertSettings: PSNAlertSettings {
            settings.draft
        }

        /// The senders whose alerts are muted.
        public var muted: [String] {
            alertSettings.mutedSenders
        }
    }

    /// Events the alerts react to.
    public enum Action: Equatable, Sendable {
        /// The hosting view watches this account, or stops watching when it cannot be watched; the watch lasts as
        /// long as the view's task for the account and the ``State/generation``.
        case watch(ProfileID?)

        /// The account's watch should start afresh, such as after a sign-in renewed its credentials; moves to the
        /// next ``State/generation``, which the hosting view watches again.
        case restart(ProfileID)

        /// The watch started by an operation reported an alert.
        case arrived(UUID, PSNAlert)

        /// The watch started by an operation ended.
        case watchEnded(UUID)

        /// The message window of a sender ended during the watch started by an operation.
        case messageWindowEnded(UUID, String)

        /// The Notifications panel opened.
        case opened

        /// The Notifications panel closed.
        case closed

        /// The system reported whether it shows the app's alerts.
        case systemAlertsChecked(PlatformClient.NotificationPermission)

        /// The person asked for the list again.
        case refresh

        /// The person cleared the list, deleting its invitations from the account's notifications.
        case clearAll

        /// PSN answered the clear started by an operation, with why it failed or `nil`.
        case cleared(UUID, CloudInvitationFailure?)

        /// PSN answered the listing started by an operation.
        case listed(UUID, Result<[CloudGameInvitation], CloudInvitationFailure>)

        /// The person asked a home PS5 to join a party session.
        case joinParty(String, HardwareID)

        /// The person asked a home PS5 to join an invitation's game session.
        case joinGame(String, HardwareID)

        /// The home PS5 join started by an operation finished, with why it failed or `nil`.
        case homeJoinFinished(UUID, CloudInvitationFailure?)

        /// The person asked to play on the home PS5 that joined a game, with Remote Play.
        case playOn(HardwareID)

        /// The person asked to start the invitation's game in the cloud and join the invitation once it plays.
        case playInCloud(String)

        /// The person muted or unmuted a sender.
        case setMuted(String, Bool)

        /// The person switched invitation alerts on or off.
        case setInvitations(Bool)

        /// The person switched message alerts on or off.
        case setMessages(Bool)

        /// The stored alert settings.
        case settings(PersistedSettingFeature<PSNAlertSettings>.Action)

        /// The person opened the account's conversations.
        case openConversations

        /// The person opened the conversation the message entry with this id was sent in.
        case reply(String)

        /// The conversations or the conversation shown in place of the list acted.
        case destination(PresentationAction<Destination.Action>)

        /// A request for the hosting feature.
        case delegate(Delegate)
    }

    /// Requests for the hosting feature.
    public enum Delegate: Equatable, Sendable {
        /// An alert should show in the running stream, when there is one.
        case show(CloudSystemNotice)
        /// The person wants to play on this home PS5 with Remote Play, after it joined a game.
        case playOn(HardwareID)
        /// The person wants to start this invitation's game in the cloud and join the invitation once it plays.
        case playInCloud(CloudGameInvitation)
    }

    /// Cancellation identifiers for the alerts' long-running work.
    public enum CancelID: Hashable, Sendable {
        /// The push channel watch.
        case watch

        /// The latest listing.
        case listing

        /// The latest clear.
        case clearing

        /// The latest party join.
        case homeJoin

        /// The wait before an ended watch starts again.
        case rewatch

        /// The wait for this sender's message window to end.
        case messageWindow(String)
    }

    /// The most entries kept.
    public static let itemLimit = 50

    @Dependency(\.streamSession) private var client
    @Dependency(\.platform) private var platform
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date.now) private var now
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.logger) private var logger

    /// How long after a watch ends, while the account is still selected, it starts again.
    public static let rewatchPause: Duration = .seconds(60)

    /// Creates the reducer.
    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.settings, action: \.settings) {
            PersistedSettingFeature<PSNAlertSettings>()
        }
        Reduce { state, action in
            switch action {
            case .watch(let profile):
                return watch(profile, state: &state)
            case .restart(let profile):
                guard state.watch.profile == profile else {
                    return .none
                }
                state.generation += 1
                state.watch = .ended(profile)
                return .merge(note("Alerts: watching again"), .cancel(id: CancelID.watch))
            case let .arrived(operation, alert):
                guard case .watching(_, operation) = state.watch else {
                    return .none
                }
                return .merge(Self.refreshList(for: alert, state: state), arrived(alert, state: &state))
            case let .messageWindowEnded(operation, sender):
                guard case .watching(_, operation) = state.watch else {
                    return .none
                }
                return catchUp(sender, state: &state)
            case .watchEnded(let operation):
                guard case .watching(let profile, operation) = state.watch else {
                    return .none
                }
                state.watch = .ended(profile)
                return .merge(
                    note(
                        "Alerts: the watch ended; watching again in \(Self.rewatchPause.components.seconds) s"
                    ),
                    .run { [clock] send in
                        try await clock.sleep(for: Self.rewatchPause)
                        await send(.restart(profile))
                    }
                    .cancellable(id: CancelID.rewatch, cancelInFlight: true)
                )
            case .systemAlertsChecked(let permission):
                state.systemAlerts = permission
                return .none
            case .opened:
                state.panel = .open
                state.unseen = 0
                let waits = forgetHeldMessages(&state)
                let permission: Effect<Action> = .run { [platform] send in
                    await send(.systemAlertsChecked(platform.notificationPermission()))
                }
                guard case .ended(let profile) = state.watch else {
                    return .merge(waits, permission, .send(.refresh))
                }
                return .merge(waits, permission, .send(.refresh), .send(.restart(profile)))
            case .refresh:
                return list(&state)
            case .clearAll:
                return clearAll(&state)
            case let .cleared(operation, failure):
                guard case .clearing(operation) = state.clearing else {
                    return .none
                }
                guard let failure else {
                    state.clearing = .idle
                    state.clearingDropped = []
                    return .none
                }
                state.clearing = .failed(failure)
                state.dropped.subtract(state.clearingDropped)
                state.clearingDropped = []
                return list(&state)
            case let .listed(operation, result):
                guard case .loading(operation) = state.listing else {
                    return .none
                }
                switch result {
                case .success(let invitations):
                    state.listing = .idle
                    merge(invitations, state: &state)
                case .failure(let failure):
                    state.listing = .failed(failure)
                }
                return .none
            case let .joinParty(session, console):
                return joinOnHome(session, on: console, game: false, state: &state)
            case let .joinGame(session, console):
                return joinOnHome(session, on: console, game: true, state: &state)
            case .playOn(let console):
                return .send(.delegate(.playOn(console)))
            case .playInCloud(let id):
                guard let item = state.items.first(where: { $0.id == id }),
                      case .invitation(let invitation) = item.kind else {
                    return .none
                }
                return .send(.delegate(.playInCloud(invitation)))
            case let .homeJoinFinished(operation, failure):
                guard case let .joining(session, console, operation) = state.homeJoin else {
                    return .none
                }
                guard let failure else {
                    state.homeJoin = .joined(session: session, console: console)
                    return note("Alerts: a home PS5 joined the party")
                }
                state.homeJoin = .failed(session: session, console: console, failure)
                return note("Alerts: the party join failed: \(failure)")
            case let .setMuted(sender, muted):
                var settings = state.alertSettings
                settings.setMuted(sender, muted)
                return .send(.settings(.edit(settings)))
            case .setInvitations(let enabled):
                var settings = state.alertSettings
                settings.invitations = enabled
                return .send(.settings(.edit(settings)))
            case .setMessages(let enabled):
                var settings = state.alertSettings
                settings.messages = enabled
                return .send(.settings(.edit(settings)))
            case .openConversations:
                guard let profile = state.watch.profile else {
                    return .none
                }
                state.destination = .conversations(ConversationsFeature.State(profile: profile))
                return .none
            case .reply(let id):
                guard let profile = state.watch.profile,
                      let item = state.items.first(where: { $0.id == id }),
                      case .message(let message) = item.kind,
                      !message.groupID.isEmpty, !message.threadID.isEmpty else {
                    return .none
                }
                state.destination = .conversation(ConversationFeature.State(
                    profile: profile,
                    groupID: message.groupID,
                    threadID: message.threadID,
                    title: message.sender.isEmpty
                        ? String(localized: .notificationsConversationDefaultTitle)
                        : message.sender
                ))
                return .none
            case .closed:
                state.panel = .closed
                return .none
            case .settings, .delegate, .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func watch(_ profile: ProfileID?, state: inout State) -> Effect<Action> {
        if let profile, profile == state.watch.profile {
            guard case .ended = state.watch else {
                return .none
            }
            return start(profile, state: &state)
        }
        state.items = []
        state.unseen = 0
        state.gate = PSNAlertGate()
        state.listing = .idle
        state.clearing = .idle
        state.homeJoin = .idle
        state.destination = nil
        state.dropped = []
        state.foldedNotificationIDs = []
        state.clearingDropped = []
        let waits = forgetHeldMessages(&state)
        guard let profile else {
            guard state.watch != .off else {
                return waits
            }
            state.watch = .off
            return .merge(
                note("Alerts: stopped watching"),
                .cancel(id: CancelID.rewatch),
                waits,
                .cancel(id: CancelID.watch),
                .cancel(id: CancelID.listing),
                .cancel(id: CancelID.clearing),
                .cancel(id: CancelID.homeJoin)
            )
        }
        return .merge(
            note("Alerts: watching the selected account"),
            .cancel(id: CancelID.rewatch),
            waits,
            .cancel(id: CancelID.listing),
            .cancel(id: CancelID.clearing),
            .cancel(id: CancelID.homeJoin),
            .send(.settings(.appeared)),
            start(profile, state: &state)
        )
    }

    private func start(_ profile: ProfileID, state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.watch = .watching(profile, operation)
        return .run { [client] send in
            for await alert in client.psnAlerts(profile) {
                await send(.arrived(operation, alert))
            }
            await send(.watchEnded(operation))
        }
        .cancellable(id: CancelID.watch, cancelInFlight: true)
    }

    private func arrived(_ alert: PSNAlert, state: inout State) -> Effect<Action> {
        let item: Item
        switch alert {
        case .invitation(let invitation):
            let id = "invitation:\(invitation.id)"
            guard !state.items.contains(where: { $0.id == id }) else {
                return .none
            }
            item = Item(id: id, kind: .invitation(invitation), arrived: now)
        case .party(let party):
            let id = "party:\(party.sessionID)"
            guard !state.items.contains(where: { $0.id == id }) else {
                return .none
            }
            item = Item(id: id, kind: .party(party), arrived: now)
        case .message(let message):
            if let shown = Self.refreshShown(message, state: state) {
                return shown
            }
            item = Item(id: "message:\(uuid().uuidString)", kind: .message(message), arrived: now)
        }
        let decision = state.gate.admit(
            sender: item.sender,
            isInvitation: item.isInvitation,
            settings: state.alertSettings,
            now: now
        )
        if case .quiet(.repeated(let count)) = decision,
           let earlier = state.items.firstIndex(where: {
               $0.sender == item.sender && $0.isInvitation == item.isInvitation
           }) {
            let folded = state.items.remove(at: earlier)
            if folded.id != item.id {
                state.dropped.insert(folded.id)
                state.foldedNotificationIDs += folded.notificationIDs
            }
            var latest = item
            latest.repeats = count
            insert(latest, state: &state)
            countUnseen(&state)
            return item.isInvitation
                ? .none
                : holdMessage(from: item.sender, state: &state)
        }
        insert(item, state: &state)
        switch decision {
        case .show:
            countUnseen(&state)
            return raise(item.id, item.notice)
        case .quiet(.repeated), .quiet(.busy):
            countUnseen(&state)
            return .none
        case .quiet(.kindOff), .quiet(.muted):
            return .none
        }
    }

    /// Reads the shown conversation list again when a message arrives outside the conversation opened from it.
    ///
    /// - Parameters:
    ///   - alert: What arrived.
    ///   - state: The panel's state.
    /// - Returns: The refresh, or nothing when no list is shown, the alert is not a message, or the message
    ///   belongs to the conversation opened from the list.
    static func refreshList(for alert: PSNAlert, state: State) -> Effect<Action> {
        guard case .message(let message) = alert, case .conversations(let list) = state.destination,
              list.conversation?.groupID != message.groupID else {
            return .none
        }
        return .send(.destination(.presented(.conversations(.refresh))))
    }

    /// Reads a shown conversation again when a message arrives in it, instead of listing and alerting the
    /// message.
    ///
    /// - Parameters:
    ///   - message: The message that arrived.
    ///   - state: The panel's state.
    /// - Returns: The refresh, or `nil` when the message's conversation is not shown.
    static func refreshShown(_ message: PSNMessageAlert, state: State) -> Effect<Action>? {
        switch state.destination {
        case .conversation(let conversation) where conversation.groupID == message.groupID:
            return .send(.destination(.presented(.conversation(.refresh))))
        case .conversations(let list) where list.conversation?.groupID == message.groupID:
            return .send(.destination(.presented(.conversations(.conversation(.presented(.refresh))))))
        case .conversations, .conversation, nil:
            return nil
        }
    }

    private func note(_ text: String) -> Effect<Action> {
        .run { [logger] _ in
            await logger.log(.diagnostic(.app, .info, text))
        }
    }

    private func countUnseen(_ state: inout State) {
        if state.panel == .closed {
            state.unseen += 1
        }
    }

    private func raise(_ id: String, _ notice: CloudSystemNotice) -> Effect<Action> {
        .merge(
            .send(.delegate(.show(notice))),
            .run { [platform] _ in
                await platform.postNotification(id, notice.title, notice.detail)
            }
        )
    }

    private func holdMessage(from sender: String, state: inout State) -> Effect<Action> {
        let held = state.heldMessages[sender, default: 0]
        state.heldMessages[sender] = held + 1
        guard held == 0, case .watching(_, let operation) = state.watch,
              let left = state.gate.remaining(sender: sender, isInvitation: false, now: now) else {
            return .none
        }
        return .run { [clock] send in
            try await clock.sleep(for: left)
            await send(.messageWindowEnded(operation, sender))
        }
        .cancellable(id: CancelID.messageWindow(sender), cancelInFlight: true)
    }

    private func catchUp(_ sender: String, state: inout State) -> Effect<Action> {
        guard let held = state.heldMessages.removeValue(forKey: sender), held > 0,
              state.panel == .closed else {
            return .none
        }
        guard state.gate.admitSummary(sender: sender, settings: state.alertSettings, now: now) == .show else {
            return .none
        }
        let name = sender.isEmpty
            ? String(localized: .notificationsNoticeFriend)
            : sender
        let notice = CloudSystemNotice(
            kind: .message,
            title: String(localized: .notificationsNoticeSentMessages(name: name, count: held + 1))
        )
        return raise("message:catch-up:\(uuid().uuidString)", notice)
    }

    private func forgetHeldMessages(_ state: inout State) -> Effect<Action> {
        let senders = Array(state.heldMessages.keys)
        state.heldMessages = [:]
        return .merge(senders.map {
            .cancel(id: CancelID.messageWindow($0))
        })
    }

    private func insert(_ item: Item, state: inout State) {
        state.items.insert(item, at: 0)
        if state.items.count > Self.itemLimit {
            state.items.removeLast(state.items.count - Self.itemLimit)
        }
    }

    private func clearAll(_ state: inout State) -> Effect<Action> {
        guard let profile = state.watch.profile else {
            return .none
        }
        let ids = state.items.flatMap(\.notificationIDs) + state.foldedNotificationIDs
        state.clearingDropped = Set(state.items.map(\.id))
        state.dropped.formUnion(state.clearingDropped)
        state.foldedNotificationIDs = []
        state.items = []
        state.unseen = 0
        let waits = forgetHeldMessages(&state)
        let operation = uuid()
        state.clearing = .clearing(operation)
        return .merge(
            waits,
            .cancel(id: CancelID.listing),
            .run { [client] send in
                do throws(CloudInvitationFailure) {
                    try await client.dismissNotifications(profile, ids)
                    await send(.cleared(operation, nil))
                } catch {
                    await send(.cleared(operation, error))
                }
            }
            .cancellable(id: CancelID.clearing, cancelInFlight: true)
        )
    }

    private func list(_ state: inout State) -> Effect<Action> {
        guard let profile = state.watch.profile else {
            return .none
        }
        let operation = uuid()
        state.listing = .loading(operation)
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                let invitations = try await client.invitations(profile)
                await send(.listed(operation, .success(invitations)))
            } catch {
                await send(.listed(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.listing, cancelInFlight: true)
    }

    private func joinOnHome(
        _ session: String,
        on console: HardwareID,
        game: Bool,
        state: inout State
    ) -> Effect<Action> {
        guard let profile = state.watch.profile else {
            return .none
        }
        if case .joining(session, console, _) = state.homeJoin {
            return .none
        }
        let operation = uuid()
        state.homeJoin = .joining(session: session, console: console, operation: operation)
        return .merge(
            note(game
                ? "Alerts: asking a home PS5 to join a game"
                : "Alerts: asking a home PS5 to join a party"),
            .run { [client] send in
                do throws(CloudInvitationFailure) {
                    if game {
                        try await client.joinOn(profile, session, console)
                    } else {
                        try await client.joinParty(profile, session, console)
                    }
                    await send(.homeJoinFinished(operation, nil))
                } catch {
                    await send(.homeJoinFinished(operation, error))
                }
            }
            .cancellable(id: CancelID.homeJoin, cancelInFlight: true)
        )
    }

    /// The entry a listed invitation becomes: a game invitation, or a party keyed as its pushes are.
    ///
    /// - Parameters:
    ///   - invitation: The listed invitation.
    ///   - now: When it was listed, used when PSN gave no time.
    /// - Returns: The entry.
    static func item(of invitation: CloudGameInvitation, now: Date) -> Item {
        switch invitation.kind {
        case .game:
            Item(
                id: "invitation:\(invitation.id)",
                kind: .invitation(invitation),
                arrived: invitation.sent ?? now
            )
        case .party:
            Item(
                id: "party:\(invitation.id)",
                kind: .party(PSNPartyAlert(
                    sender: invitation.inviter,
                    sessionID: invitation.id,
                    notificationIDs: invitation.notificationIDs
                )),
                arrived: invitation.sent ?? now
            )
        }
    }

    private func merge(_ invitations: [CloudGameInvitation], state: inout State) {
        let listed = invitations.map {
            Self.item(of: $0, now: now)
        }
        for item in listed {
            guard case .party(let party) = item.kind,
                  let index = state.items.firstIndex(where: { $0.id == item.id }),
                  case .party(var held) = state.items[index].kind else {
                continue
            }
            held.notificationIDs = party.notificationIDs
            state.items[index].kind = .party(held)
        }
        let known = Set(state.items.map(\.id)).union(state.dropped)
        let added = listed.filter {
            !known.contains($0.id)
        }
        guard !added.isEmpty else {
            return
        }
        state.items = Array((state.items + added).sorted {
            $0.arrived > $1.arrived
        }
        .prefix(Self.itemLimit))
    }
}

extension PSNAlertsFeature.Destination.State: Equatable {}
extension PSNAlertsFeature.Destination.Action: Equatable, Sendable {}
