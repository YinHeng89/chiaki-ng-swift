import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The stream menu's Invitations panel during a PS5 cloud or PS Now stream: the game invitations friends sent to
/// the game being streamed, each with a Join button when it can be joined, and a Refresh button. On a PS5 game,
/// Invite friends swaps the list for a friend picker in place: Back, Send invitations, Share link when anyone may
/// join the session, then a row for each friend. Back closes the picker with focus on Invite friends.
struct StreamMenuInvitationsControls: View {
    /// The panel's store.
    let store: StoreOf<CloudInvitationsFeature>
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus.
    let focusedControl: StreamMenuControl?

    /// The controls a controller moves through: each joinable invitation's Join button, then Refresh and, on a
    /// PS5 game, Invite friends; or, while the friend picker is open, its Back, Send and Share link buttons and a
    /// row for each friend.
    ///
    /// - Parameter state: The panel's state.
    /// - Returns: The controls in navigation order.
    static func controls(for state: CloudInvitationsFeature.State) -> [StreamMenuControl] {
        if let invite = state.invite {
            return [.inviteBack, .inviteSend] + (invite.found?.openToAnyone == true
                ? [.inviteShare]
                : []) + invite.listed.map {
                StreamMenuControl.inviteFriend($0.id)
            }
        }
        return state.shown.filter {
            $0.joining == .joinable
        }
        .map {
            StreamMenuControl.invitationJoin($0.id)
        } + [.invitationsRefresh] + (state.invitableTitle == nil
            ? []
            : [.invitationsInvite])
    }

    var body: some View {
        if let invite = store.scope(state: \.invite, action: \.invite) {
            InviteFriendsPicker(store: invite, focus: focus, focusedControl: focusedControl) {
                store.send(.inviteClosed)
                focus?.wrappedValue = .control(.invitationsInvite)
            }
            .onDisappear(perform: stopSessionLookupWhenPanelLeaves)
        } else {
            invitations
        }
    }

    private var invitations: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Invitations").font(.title2.weight(.semibold))
            content
            FocusButton(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .invitationsRefresh,
                focused: focusedControl == .invitationsRefresh
            ))
            .glassControlStyle()
            .controlSize(.large)
            if store.invitableTitle != nil {
                FocusButton(action: openInvite) {
                    Label("Invite friends", systemImage: "person.2.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .modifier(OptionalStreamMenuButtonFocus(
                    focus: focus,
                    target: .invitationsInvite,
                    focused: focusedControl == .invitationsInvite
                ))
                .glassControlStyle()
                .controlSize(.large)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private func stopSessionLookupWhenPanelLeaves() {
        if store.invite != nil {
            store.send(.inviteClosed)
        }
    }

    private func openInvite() {
        store.send(.inviteOpened)
        focus?.wrappedValue = .control(.inviteBack)
    }

    @ViewBuilder private var content: some View {
        switch store.listing {
        case .loading(_, let kept) where !kept.isEmpty:
            rows
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading game invitations")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text("Couldn't load your game invitations. Try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded:
            if store.shown.isEmpty {
                Text("Game invitations to this game will be displayed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        ForEach(store.shown) { invitation in
            row(invitation)
        }
    }

    private func refresh() {
        store.send(.refresh)
    }

    private func row(_ invitation: CloudGameInvitation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.heading(invitation)).font(.headline)
            if !invitation.sessionName.isEmpty {
                Text(invitation.sessionName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if invitation.maxPlayers > 0 {
                Text("\(invitation.players) of \(invitation.maxPlayers) players")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if invitation.joining == .joinable {
                joinButton(invitation)
            } else {
                Text(Self.unavailable(invitation.joining))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = note(for: invitation) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func joinButton(_ invitation: CloudGameInvitation) -> some View {
        FocusButton(action: join(invitation.id)) {
            Label(joinTitle(invitation), systemImage: "person.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .modifier(OptionalStreamMenuButtonFocus(
            focus: focus,
            target: .invitationJoin(invitation.id),
            focused: focusedControl == .invitationJoin(invitation.id)
        ))
        .glassProminentControlStyle()
        .controlSize(.large)
    }

    private func join(_ invitation: String) -> () -> Void {
        {
            store.send(.join(invitation))
        }
    }

    private func joinTitle(_ invitation: CloudGameInvitation) -> String {
        if case .joining(invitation.id, _) = store.joining {
            return "Joining"
        }
        return "Join"
    }

    private func note(for invitation: CloudGameInvitation) -> String? {
        switch store.joining {
        case .joined(invitation.id):
            return "Sent to your cloud console."
        case .failed(invitation.id, let failure):
            return Self.message(failure)
        default:
            return nil
        }
    }

    /// The heading of an invitation: who sent it.
    ///
    /// - Parameter invitation: The invitation.
    /// - Returns: The heading.
    static func heading(_ invitation: CloudGameInvitation) -> String {
        guard !invitation.inviter.isEmpty else {
            return "You're invited to play this game"
        }
        return "\(invitation.inviter) invited you to play"
    }

    /// Why an invitation cannot be joined, in the service's own wording.
    ///
    /// - Parameter joining: The invitation's state.
    /// - Returns: The explanation.
    static func unavailable(_ joining: CloudGameInvitation.Joining) -> String {
        switch joining {
        case .joinable:
            ""
        case .alreadyJoined:
            "You're already in this game."
        case .full:
            "This game group is already full."
        case .cannotJoin:
            "You can't join this game."
        }
    }

    /// What a failed join tells the player.
    ///
    /// - Parameter failure: Why the join failed.
    /// - Returns: The message.
    nonisolated static func message(_ failure: CloudInvitationFailure) -> String {
        switch failure {
        case .sessionEnded:
            "This game session has ended."
        case .alreadyJoined:
            "You're already in this game."
        case .full:
            "This game group is already full."
        case .cannotJoin, .rejected:
            "You can't join this game."
        case .failed:
            "The invitation couldn't be sent to your cloud console. Try again."
        case .noCloudConsole, .consoleUnavailable:
            "Couldn't find a PlayStation 5 cloud console to join on. "
                + "If this is a PlayStation 4 game, join using its PlayStation 5 version."
        case .timedOut:
            "Your cloud console didn't answer in time. Try again."
        case .signedOut, .auth:
            "Sign in to PlayStation Network again to join."
        case .unavailable, .cancelled:
            "Couldn't reach PlayStation Network. Try again."
        }
    }
}
