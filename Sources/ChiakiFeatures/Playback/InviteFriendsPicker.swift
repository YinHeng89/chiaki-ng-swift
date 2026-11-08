import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The friend picker inside the stream menu's Invitations panel: Back, Send invitations and, when anyone may join
/// the session, Share link, then the player's friends, online friends first, each picked or unpicked with Confirm.
struct InviteFriendsPicker: View {
    /// The picker's store.
    let store: StoreOf<InviteFriendsFeature>
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus.
    let focusedControl: StreamMenuControl?
    /// Closes the picker.
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FocusButton(action: close) {
                    Label(.commonBack, systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.callout.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .modifier(OptionalStreamMenuButtonFocus(
                    focus: focus,
                    target: .inviteBack,
                    focused: focusedControl == .inviteBack
                ))
                .glassControlStyle()
                .focusBorderShape(.circle)
                .accessibilityLabel(.playbackInviteBackLabel)
                Text(.playbackInviteTitle).font(.title2.weight(.semibold))
            }
            sessionLine
            FocusButton {
                store.send(.send)
            } label: {
                Label(sendTitle, systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .inviteSend,
                focused: focusedControl == .inviteSend
            ))
            .glassProminentControlStyle()
            .controlSize(.large)
            if let note = sendNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.found?.openToAnyone == true {
                shareButton
                linkView
            }
            friends
        }
    }

    @ViewBuilder private var sessionLine: some View {
        switch store.session {
        case .finding:
            Text(.playbackInviteFinding)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .found(let session):
            if session.maxPlayers > 0 {
                Text(.playbackInvitePlayers(players: session.players, maxPlayers: session.maxPlayers))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .none:
            Text(.playbackInviteNotOnline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text(.playbackInviteSessionFailed)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var sendTitle: LocalizedStringResource {
        if case .sending = store.sending {
            return .playbackInviteSending
        }
        return store.selected.isEmpty
            ? .playbackInviteSend
            : .playbackInviteSendCount(count: store.selected.count)
    }

    private var sendNote: LocalizedStringResource? {
        switch store.sending {
        case .sent(let count):
            .playbackInviteSent(count: count)
        case .failed:
            .playbackInviteSendFailed
        case .idle, .sending:
            store.found != nil && store.selected.isEmpty && !store.listed.isEmpty
                ? .playbackInvitePickHint
                : nil
        }
    }

    private var shareButton: some View {
        FocusButton {
            store.send(.share)
        } label: {
            Label(.playbackInviteShareLink, systemImage: "link")
                .frame(maxWidth: .infinity)
        }
        .modifier(OptionalStreamMenuButtonFocus(
            focus: focus,
            target: .inviteShare,
            focused: focusedControl == .inviteShare
        ))
        .glassControlStyle()
        .controlSize(.large)
    }

    @ViewBuilder private var linkView: some View {
        switch store.link {
        case .idle:
            EmptyView()
        case .loading:
            Text(.playbackInviteMakingLink)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .shown(let link):
            VStack(alignment: .leading, spacing: 8) {
                if let image = link.imageURL {
                    CloudArtworkView(url: image)
                        .frame(width: 160, height: 160)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityLabel(.playbackInviteLinkCode)
                }
                Text(link.url.absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(.playbackInviteLinkNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text(.playbackInviteLinkFailed)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var friends: some View {
        switch store.friends {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(.playbackInviteLoadingFriends)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text(.playbackInviteFriendsFailed)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded(let friends):
            if friends.isEmpty {
                Text(.playbackInviteNoFriends)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(friends) { friend in
                    row(friend)
                }
            }
        }
    }

    private func row(_ friend: PSNFriend) -> some View {
        let picked = store.selected.contains(friend.id)
        return FocusButton {
            store.send(.toggled(friend.id))
        } label: {
            HStack(spacing: 12) {
                CloudArtworkView(url: friend.avatarURL)
                    .frame(width: 36, height: 36)
                    .clipShape(.circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(Self.status(of: friend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: picked
                    ? "checkmark.circle.fill"
                    : "circle")
                    .font(.title3)
                    .foregroundStyle(picked
                        ? Palette.accent
                        : .secondary)
                        .accessibilityHidden(true)
            }
            .padding(6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(OptionalStreamMenuButtonFocus(
            focus: focus,
            target: .inviteFriend(friend.id),
            focused: focusedControl == .inviteFriend(friend.id)
        ))
        .focusHighlightShape(.roundedRectangle(10))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked
            ? .isSelected
            : [])
    }

    /// The line under a friend's name: what they play, or whether they are online.
    ///
    /// - Parameter friend: The friend.
    /// - Returns: The line.
    static func status(of friend: PSNFriend) -> LocalizedStringResource {
        guard friend.online else {
            return .playbackInviteOffline
        }
        return friend.playing.isEmpty
            ? .playbackInviteOnline
            : .playbackInvitePlaying(game: friend.playing)
    }
}
