import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The Notifications panel the library's bell opens: the game and party invitations and messages PSN told the
/// account about, with Reply on each message and Mute on each sender, a Join button for each of the account's PS5s
/// under a party invitation or a joinable game invitation, a Play button once a PS5 joined a game, the switches for
/// which kinds raise an alert, and the muted senders. A Messages row
/// opens the account's conversations, and Reply opens a message's conversation, each in place of the list.
///
/// Refresh and Clear all share the top row, an entry's Reply and Mute share theirs, and an invitation's Join
/// buttons share theirs; every other control, the Messages row included, is a row of its own. Up and Down move between
/// rows, Left and Right along a row, Back closes the panel and focus starts on Refresh, or on the control that
/// opened a conversation when the panel comes back from it.
struct PSNAlertsPanel: View {
    /// A focus stop of the panel.
    enum Focus: Hashable {
        /// The Messages button, which opens the conversations.
        case conversations
        /// The Refresh button.
        case refresh
        /// The Clear all button.
        case clearAll
        /// The Mute or Unmute button of the entry with this id.
        case mute(String)
        /// The Reply button of the message entry with this id.
        case reply(String)
        /// The Join button of the party or game invitation entry with this id for this console.
        case joinHome(String, HardwareID)
        /// The Play button of the game invitation entry with this id, which starts Remote Play to the console that
        /// joined it.
        case playOn(String, HardwareID)
        /// The Play in the cloud button of the game invitation entry with this id.
        case playInCloud(String)
        /// The game invitation alerts switch.
        case invitations
        /// The message alerts switch.
        case messages
        /// The Unmute button of this muted sender.
        case unmute(String)
    }

    /// The account's alerts.
    let store: StoreOf<PSNAlertsFeature>
    /// The account's PS5s that can join a party or a game.
    var consoles: [PSNAlertsFeature.PartyConsole] = []
    /// The game invitation entries whose game the account can play in the cloud, which offer Play in the cloud.
    var cloudPlayable: Set<String> = []
    /// Closes the panel.
    let close: () -> Void
    @MenuFocusState private var focus: Focus?
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hostWindow: PlatformWindow?
    @State private var listHeight: CGFloat = Self.listLimit
    @State private var returnFocus: Focus?

    /// The tallest the list grows before it scrolls.
    static let listLimit: CGFloat = 360

    var body: some View {
        Group {
            if let conversation = store.scope(
                state: \.destination?.conversation,
                action: \.destination.conversation
            ) {
                ConversationView(store: conversation) {
                    store.send(.destination(.dismiss))
                }
            } else if let conversations = store.scope(
                state: \.destination?.conversations,
                action: \.destination.conversations
            ) {
                ConversationsView(store: conversations) {
                    store.send(.destination(.dismiss))
                }
            } else {
                alerts
            }
        }
        .padding(20)
        .background(WindowAccessor { hostWindow = $0 })
        .onChange(of: hostWindow) { old, window in
            if let old {
                WindowFocus(old).releaseInput()
            }
            if let window {
                WindowFocus(window).claimInput()
            }
        }
        .onDisappear {
            if let hostWindow {
                WindowFocus(hostWindow).releaseInput()
            }
        }
        .menuHandlers(back: { window in
            guard window === hostWindow else {
                return false
            }
            stepOut()
            return true
        })
    }

    /// Steps out one level for the controller's Back: from a conversation to the list it came from or to the
    /// panel, from the list to the panel, and from the panel closes it. A popover closes itself on Escape, so
    /// Back is answered here rather than left to become one.
    private func stepOut() {
        switch store.destination {
        case .conversations(let list) where list.conversation != nil:
            store.send(.destination(.presented(.conversations(.conversation(.dismiss)))))
        case .conversations, .conversation:
            store.send(.destination(.dismiss))
        case nil:
            close()
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            conversationsButton
            if let note = Self.systemAlertsNote(store.systemAlerts) {
                Label(note, systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            entries
            Divider()
            switches
            if !store.muted.isEmpty {
                mutedSenders
            }
        }
        .frame(width: 400, alignment: .leading)
        .onAppear {
            let initial = returnFocus.flatMap { stop in
                rows.joined().contains(stop)
                    ? stop
                    : nil
            } ?? .refresh
            let returning = returnFocus != nil
            returnFocus = nil
            focus = initial
            if returning {
                FocusRestore.settle(initial) {
                    focus
                } write: { stop in
                    focus = stop
                }
            }
            navigator?.ensureFocus(
                in: { hostWindow },
                reset: {},
                apply: {
                    guard focus == nil else {
                        return
                    }
                    focus = initial
                }
            )
        }
        .onMenuExitCommand {
            close()
        }
    }

    /// The panel's stops, row by row.
    var rows: [[Focus]] {
        let muteEntries = Set(Self.muteEntries(in: store.items))
        let entries = store.items.flatMap { item -> [[Focus]] in
            var rows: [[Focus]] = []
            var row: [Focus] = []
            if Self.replies(item) {
                row.append(.reply(item.id))
            }
            if muteEntries.contains(item.id) {
                row.append(.mute(item.id))
            }
            if !row.isEmpty {
                rows.append(row)
            }
            if Self.joinsOnHome(item), !consoles.isEmpty {
                rows.append(consoles.map {
                    .joinHome(item.id, $0.hardwareID)
                })
                if let console = playable(item) {
                    rows.append([.playOn(item.id, console)])
                }
            }
            if cloudPlayable.contains(item.id) {
                rows.append([.playInCloud(item.id)])
            }
            return rows
        }
        return [[.refresh] + (store.items.isEmpty
                ? []
                : [.clearAll]), [.conversations]] + entries + [[.invitations], [.messages]] + store.muted
            .map {
                [.unmute($0)]
            }
    }

    /// Whether an entry offers Reply: a message whose push named its conversation's thread.
    ///
    /// - Parameter item: The entry.
    /// - Returns: `true` for a message that can be answered.
    static func replies(_ item: PSNAlertsFeature.Item) -> Bool {
        guard case .message(let message) = item.kind else {
            return false
        }
        return !message.groupID.isEmpty && !message.threadID.isEmpty
    }

    /// Whether an entry offers Join buttons on the account's PS5s: a party invitation, or a game invitation to a
    /// SessionManager session that can be joined.
    ///
    /// - Parameter item: The entry.
    /// - Returns: `true` for a party or a joinable PS5 game invitation.
    static func joinsOnHome(_ item: PSNAlertsFeature.Item) -> Bool {
        switch item.kind {
        case .party:
            true
        case .invitation(let invitation):
            invitation.kind == .game && invitation.joining == .joinable
                && CloudInvitationsFeature.joinsByGameIntent(invitation)
        case .message:
            false
        }
    }

    /// The console a game invitation entry offers Play on: the PS5 that joined its session.
    ///
    /// - Parameter item: The entry.
    /// - Returns: The console, or `nil` when no PS5 joined this entry's game.
    private func playable(_ item: PSNAlertsFeature.Item) -> HardwareID? {
        guard case .invitation(let invitation) = item.kind,
              case .joined(invitation.id, let console) = store.homeJoin else {
            return nil
        }
        return console
    }

    /// The entries that carry their sender's Mute button: each sender's newest entry.
    ///
    /// - Parameter items: The entries, newest first.
    /// - Returns: The entries' ids, in list order.
    static func muteEntries(in items: [PSNAlertsFeature.Item]) -> [String] {
        var senders = Set<String>()
        return items.compactMap { item in
            guard !item.sender.isEmpty, senders.insert(item.sender).inserted else {
                return nil
            }
            return item.id
        }
    }

    /// The stop a direction moves focus to.
    ///
    /// - Parameters:
    ///   - current: The focused stop.
    ///   - rows: The panel's stops, row by row.
    ///   - direction: The direction pressed.
    /// - Returns: The next stop, or `nil` when focus stays.
    nonisolated static func move(from current: Focus, in rows: [[Focus]],
                                 _ direction: MenuMoveDirection) -> Focus? {
        FocusRows.move(from: current, in: rows, direction)
    }

    private var header: some View {
        HStack {
            Text("Notifications").font(.title3.weight(.semibold))
            Spacer()
            stopButton(.refresh) {
                store.send(.refresh)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.medium))
            }
            .focusBorderShape(.capsule)
            if !store.items.isEmpty {
                stopButton(.clearAll) {
                    focus = .refresh
                    store.send(.clearAll)
                } label: {
                    Label("Clear all", systemImage: "trash")
                        .font(.callout.weight(.medium))
                }
                .focusBorderShape(.capsule)
            }
        }
    }

    private var conversationsButton: some View {
        stopButton(.conversations) {
            returnFocus = .conversations
            store.send(.openConversations)
        } label: {
            HStack {
                Label("Messages", systemImage: "bubble.left.and.bubble.right")
                Spacer()
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
        }
        .focusBorderShape(.capsule)
        .accessibilityLabel("Messages")
    }

    @ViewBuilder private var entries: some View {
        if store.items.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let muteEntries = Set(Self.muteEntries(in: store.items))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.items) { item in
                            row(item, mutes: muteEntries.contains(item.id))
                                .id(item.id)
                        }
                    }
                    .padding(6)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { height in
                        listHeight = height
                    }
                }
                .selfManagedFocusScrolling()
                .frame(height: min(listHeight, Self.listLimit))
                .onChange(of: focus) { _, focused in
                    let target: String?
                    switch focused {
                    case .mute(let id), .reply(let id), .joinHome(let id, _), .playOn(let id, _),
                         .playInCloud(let id):
                        target = id
                    case .refresh:
                        target = store.items.first?.id
                    default:
                        target = nil
                    }
                    guard let target else {
                        return
                    }
                    withAnimation(reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(target)
                        }
                }
            }
        }
    }

    private var emptyText: String {
        switch store.listing {
        case .loading:
            "Loading notifications"
        case .failed:
            "Couldn't load your game invitations. Try again."
        case .idle:
            "Nothing new. Invitations and messages will appear here."
        }
    }

    private func row(_ item: PSNAlertsFeature.Item, mutes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            entry(item, mutes: mutes)
            if Self.joinsOnHome(item), !consoles.isEmpty {
                switch item.kind {
                case .party(let party):
                    homeJoin(item.id, session: party.sessionID, game: false)
                case .invitation(let invitation):
                    homeJoin(item.id, session: invitation.id, game: true)
                case .message:
                    EmptyView()
                }
            }
            if cloudPlayable.contains(item.id) {
                stopButton(.playInCloud(item.id)) {
                    store.send(.playInCloud(item.id))
                } label: {
                    Label("Play in the cloud", systemImage: AppIcon.cloud.rawValue)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                .focusBorderShape(.capsule)
                .padding(.leading, 44)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func homeJoin(_ id: String, session: String, game: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if consoles.count > 1 {
                Text(game
                    ? "Join the game on"
                    : "Join the party on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(consoles) { console in
                    stopButton(.joinHome(id, console.hardwareID)) {
                        store.send(game
                            ? .joinGame(session, console.hardwareID)
                            : .joinParty(session, console.hardwareID))
                    } label: {
                        Label(joinTitle(session: session, console: console), systemImage: game
                            ? "gamecontroller.fill"
                            : "person.2.fill")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .focusBorderShape(.capsule)
                }
            }
            if let note = Self.joinNote(store.homeJoin, session: session, game: game, consoles: consoles) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if game, case .joined(session, let console) = store.homeJoin {
                stopButton(.playOn(id, console)) {
                    store.send(.playOn(console))
                } label: {
                    Label(
                        "Play on \(consoles.first { $0.hardwareID == console }?.name ?? "your PS5")",
                        systemImage: "play.fill"
                    )
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                }
                .focusBorderShape(.capsule)
            }
        }
        .padding(.leading, 44)
    }

    private func joinTitle(session: String, console: PSNAlertsFeature.PartyConsole) -> String {
        if case .joining(session, console.hardwareID, _) = store.homeJoin {
            return "Joining"
        }
        return consoles.count > 1
            ? console.name
            : "Join on \(console.name)"
    }

    /// The line under an invitation's Join buttons about its latest join on a PS5.
    ///
    /// - Parameters:
    ///   - join: Where the latest home PS5 join stands.
    ///   - session: The party or game session shown.
    ///   - game: Whether the invitation is to a game rather than a party.
    ///   - consoles: The consoles offered.
    /// - Returns: The line, or `nil` when the latest join is about another session or none was asked for.
    static func joinNote(
        _ join: PSNAlertsFeature.HomeJoin,
        session: String,
        game: Bool,
        consoles: [PSNAlertsFeature.PartyConsole]
    ) -> String? {
        let what = game
            ? "game"
            : "party"
        guard join.session == session else {
            return nil
        }
        let name = { (console: HardwareID) in
            consoles.first { $0.hardwareID == console }?.name ?? "Your PS5"
        }
        switch join {
        case .idle, .joining:
            return nil
        case .joined(_, let console):
            return game
                ? "\(name(console)) joined the game. Play on it with Remote Play."
                : "\(name(console)) joined the party. Connect to it with Remote Play to hear and talk."
        case let .failed(_, console, failure):
            switch failure {
            case .sessionEnded, .cannotJoin, .full, .alreadyJoined:
                return "You can't join this \(what)."
            case .rejected:
                return "PlayStation Network didn't let \(name(console)) join the \(what)."
            case .failed:
                return "\(name(console)) couldn't join the \(what). Try again."
            case .noCloudConsole, .consoleUnavailable:
                return "\(name(console)) can't be reached through PlayStation Network. Check that it's a PS5 "
                    + "paired with this account."
            case .timedOut:
                return "\(name(console)) didn't answer in time. Try again."
            case .signedOut, .auth:
                return "Sign in to PlayStation Network again to join."
            case .unavailable, .cancelled:
                return "Couldn't reach PlayStation Network. Try again."
            }
        }
    }

    private func entry(_ item: PSNAlertsFeature.Item, mutes: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: Self.symbol(of: item))
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Palette.accent.opacity(0.22), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.notice.title).font(.headline).lineLimit(2)
                ForEach(Self.details(of: item), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if Self.replies(item) {
                stopButton(.reply(item.id)) {
                    returnFocus = .reply(item.id)
                    store.send(.reply(item.id))
                } label: {
                    Text("Reply").font(.callout.weight(.medium))
                }
                .focusBorderShape(.capsule)
                .accessibilityLabel("Reply to \(item.sender)")
            }
            if mutes {
                let muted = store.alertSettings.isMuted(item.sender)
                stopButton(.mute(item.id)) {
                    store.send(.setMuted(item.sender, !muted))
                } label: {
                    Text(muted
                        ? "Unmute"
                        : "Mute")
                        .font(.callout.weight(.medium))
                }
                .focusBorderShape(.capsule)
                .accessibilityLabel(muted
                    ? "Unmute \(item.sender)"
                    : "Mute \(item.sender)")
            }
        }
    }

    /// The symbol beside an entry.
    ///
    /// - Parameter item: The entry.
    /// - Returns: The SF Symbol name.
    static func symbol(of item: PSNAlertsFeature.Item) -> String {
        switch item.kind {
        case .invitation:
            "person.badge.plus"
        case .party:
            "person.2.fill"
        case .message:
            "message.fill"
        }
    }

    /// The line about macOS notifications: why the app asks, or how to turn them back on.
    ///
    /// - Parameter permission: Whether macOS shows the app's alerts, or `nil` before it was checked.
    /// - Returns: The line, or `nil` when there is nothing to say.
    static func systemAlertsNote(_ permission: PlatformClient.NotificationPermission?) -> String? {
        switch permission {
        case .notAsked:
            "chiaki-ng asks to show macOS notifications, so it can tell you about invitations and messages "
                + "while it isn't in front."
        case .denied:
            "macOS notifications are off for chiaki-ng, so alerts only show inside the app. Turn them on in "
                + "System Settings, Notifications."
        case .allowed, nil:
            nil
        }
    }

    /// The lines under an entry's title: the session's name, how many times its sender asked, and when.
    ///
    /// - Parameter item: The entry.
    /// - Returns: The lines.
    static func details(of item: PSNAlertsFeature.Item) -> [String] {
        var lines: [String] = []
        if !item.notice.detail.isEmpty {
            lines.append(item.notice.detail)
        }
        if item.repeats > 1 {
            lines.append(item.isInvitation
                ? "Invited you \(item.repeats) times"
                : "Sent \(item.repeats) messages")
        }
        lines.append(item.arrived.formatted(.relative(presentation: .named)))
        return lines
    }

    private var switches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alert me about").font(.callout.weight(.semibold))
            switchRow("Invitations", isOn: store.alertSettings.invitations, stop: .invitations) {
                store.send(.setInvitations(!store.alertSettings.invitations))
            }
            switchRow("Messages", isOn: store.alertSettings.messages, stop: .messages) {
                store.send(.setMessages(!store.alertSettings.messages))
            }
        }
    }

    private var mutedSenders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muted").font(.callout.weight(.semibold))
            ForEach(store.muted, id: \.self) { sender in
                HStack {
                    Text(sender).font(.callout)
                    Spacer()
                    stopButton(.unmute(sender)) {
                        store.send(.setMuted(sender, false))
                    } label: {
                        Text("Unmute").font(.callout.weight(.medium))
                    }
                    .focusBorderShape(.capsule)
                    .accessibilityLabel("Unmute \(sender)")
                }
            }
        }
    }

    private func switchRow(
        _ title: String,
        isOn: Bool,
        stop: Focus,
        action: @escaping () -> Void
    ) -> some View {
        FocusButton(action: action) {
            HStack(spacing: 8) {
                PSNAlertsCheckbox(isOn: isOn)
                Text(title)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(6))
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn
            ? "On"
            : "Off")
            .accessibilityAddTraits(.isToggle)
    }

    private func stopButton(
        _ stop: Focus,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let content = label()
        return FocusButton(action: action) {
            content
        }
        .glassControlStyle()
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
    }

    private func move(from current: Focus, _ direction: MenuMoveDirection) {
        if let next = Self.move(from: current, in: rows, direction) {
            focus = next
        }
    }
}

/// The checkbox drawn in a Notifications panel switch row: the app's accent box, filled when on.
private struct PSNAlertsCheckbox: View {
    /// Whether the switch is on.
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    isOn
                        ? Palette.accent
                        : Color.primary.opacity(0.08)
                )
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    isOn
                        ? Color.clear
                        : Color.primary.opacity(0.3),
                    lineWidth: 1
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
