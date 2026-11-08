import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// The remote players part of the stream menu's players panel: the invite button and guests still joining.
struct KakusanPlayersSection: View {
    /// The host feature.
    let store: StoreOf<KakusanHostFeature>
    /// The couch seats, to leave out guests who already have one.
    let seats: CouchSeats
    /// The stream menu's controller focus.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that has focus.
    var focusedControl: StreamMenuControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(.kakusanPlayersTitle)
                    .font(.headline)
                Spacer(minLength: 12)
                button(
                    .kakusanPlayersInvite,
                    symbol: "person.badge.plus",
                    target: .remote(.invite),
                    prominent: true
                ) {
                    store.send(.invite)
                }
                .disabled(!store.invitesOpen)
                .frame(maxWidth: 200)
            }
            if case .unavailable(let error) = store.hosting {
                KakusanErrorText(
                    text: .kakusanPlayersInvitesUnavailable(reason: String(localized: error.hostingLabel))
                )
            } else if let until = store.cooldownUntil {
                KakusanCountdownText(deadline: until) {
                    .kakusanPlayersCooldown(time: $0)
                }
            }
            ForEach(Self.pending(store.state, seats: seats)) { guest in
                row(guest)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
    }

    /// The guests still joining, without a couch seat.
    static func pending(
        _ state: KakusanHostFeature.State,
        seats: CouchSeats
    ) -> [KakusanHostFeature.Guest] {
        state.guests.filter { guest in
            guard let id = guest.attempt.guest else {
                return true
            }
            return seats.pad(for: id) == nil
        }
    }

    /// The section's controls in focus order.
    static func controls(for state: KakusanHostFeature.State, seats: CouchSeats) -> [StreamMenuControl] {
        var controls: [StreamMenuControl] = state.invitesOpen
            ? [.remote(.invite)]
            : []
        for guest in pending(state, seats: seats) {
            controls += [.remote(.open(guest.id)), .remote(.cancel(guest.id))]
        }
        return controls
    }

    private func row(_ guest: KakusanHostFeature.Guest) -> some View {
        let status = guest.status
        return HStack(spacing: 12) {
            Image(systemName: "person.wave.2")
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(guest.displayName)
                    .font(.callout.weight(.semibold))
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.tone.color)
            }
            Spacer(minLength: 8)
            button(.kakusanPlayersOpen, symbol: nil, target: .remote(.open(guest.id))) {
                store.send(.present(guest.id))
            }
            .frame(maxWidth: 110)
            button(guest.attempt.outcome == nil
                ? .commonCancel
                : .kakusanPlayersDismiss, symbol: nil, target: .remote(.cancel(guest.id))) {
                    if guest.attempt.outcome == nil {
                        store.send(.cancel(guest.id))
                    } else {
                        store.send(.dismiss(guest.id))
                    }
                }
                .frame(maxWidth: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 12))
    }

    private func button(
        _ title: LocalizedStringResource,
        symbol: String?,
        target: StreamMenuControl,
        prominent: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent {
                FocusButton(action: perform) {
                    label(title, symbol: symbol)
                }
                .glassProminentControlStyle()
            } else {
                FocusButton(action: perform) {
                    label(title, symbol: symbol)
                }
                .glassControlStyle()
            }
        }
        .controlSize(.small)
        .modifier(OptionalStreamMenuButtonFocus(
            focus: focus,
            target: target,
            focused: focusedControl == target
        ))
    }

    @ViewBuilder
    private func label(_ title: LocalizedStringResource, symbol: String?) -> some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A Kakusan control in the stream menu.
enum KakusanMenuControl: Hashable {
    /// The button that opens an invite for a remote player.
    case invite
    /// Opens the joining guest's invite details.
    case open(UUID)
    /// Cancels a guest still joining, or dismisses one whose attempt has ended.
    case cancel(UUID)
    /// Starts remembering a verified remote player for next time.
    case remember(UUID)
}

extension StreamMenuOverlay {
    /// Performs a Kakusan control picked with the controller.
    ///
    /// - Returns: `nil` when `control` is not a Kakusan control, otherwise `true`, including when
    ///   Kakusan is not running.
    func activateRemoteControl(_ control: StreamMenuControl) -> Bool? {
        guard case .remote(let remote) = control else {
            return nil
        }
        guard let kakusan else {
            return true
        }
        switch remote {
        case .invite:
            kakusan.send(.invite)
        case .open(let id):
            kakusan.send(.present(id))
        case .cancel(let id):
            if kakusan.state.guests[id: id]?.attempt.outcome == nil {
                kakusan.send(.cancel(id))
            } else {
                kakusan.send(.dismiss(id))
            }
        case .remember(let id):
            kakusan.send(.startRemembering(id))
        }
        return true
    }
}

extension StreamMenuPanelContent {
    /// The players panel, shown only while couch play is set up.
    @ViewBuilder
    var playersPanel: some View {
        if let couch {
            StreamPlayersPanel(
                store: couch,
                kakusan: kakusan,
                focus: focus,
                focusedControl: focusedControl
            )
        }
    }
}

extension StreamPlayersPanel {
    /// The players panel's controls in focus order, with remember controls beside verified remote players.
    static func controls(
        for state: CouchReducer.State,
        kakusan: KakusanHostFeature.State?
    ) -> [StreamMenuControl] {
        guard let kakusan, state.picking == nil else {
            return controls(for: state)
        }
        let seated = controls(for: state).flatMap { control -> [StreamMenuControl] in
            guard case .playerRemove(let pad) = control, let remote = state.seats[pad].remote,
                  let guest = kakusan.guest(for: remote.guest),
                  guest.canRemember else {
                return [control]
            }
            return [.remote(.remember(guest.id)), control]
        }
        return seated + KakusanPlayersSection.controls(for: kakusan, seats: state.seats)
    }

    /// The remote players section, shown while Kakusan is hosting and no seat is being picked.
    @ViewBuilder
    var remoteSection: some View {
        if let kakusan, store.picking == nil {
            KakusanPlayersSection(
                store: kakusan,
                seats: store.seats,
                focus: focus,
                focusedControl: focusedControl
            )
        }
    }

    /// The seat's status line, or Reserved while the pad is held for a remote player.
    func status(of pad: UInt8) -> (text: LocalizedStringResource, tone: CouchTone) {
        store.seats.heldForRemote(pad)
            ? (.kakusanPlayersReserved, .waiting)
            : store.seats[pad].status(on: store.seats.console)
    }

    /// Remote for a seat taken by a remote player, otherwise `nil`.
    func remoteTag(_ seat: CouchSeat) -> LocalizedStringResource? {
        seat.remote == nil
            ? nil
            : .kakusanPlayersRemoteTag
    }

    /// The name to show for a seat: the remote player's name or the local player's account name.
    func seatName(_ seat: CouchSeat) -> String? {
        guard let remote = seat.remote else {
            return seat.player?.account?.name
        }
        return remote.name ?? String(localized: .kakusanGuestRemotePlayer)
    }

    /// The seat's status line, replaced by the remote guest's status when there is one, and the
    /// account name under it for a remote player.
    @ViewBuilder
    func seatStatus(
        _ seat: CouchSeat,
        status: (text: LocalizedStringResource, tone: CouchTone)
    ) -> some View {
        let shown = remoteStatus(seat) ?? status
        Text(shown.text)
            .font(.callout)
            .foregroundStyle(shown.tone.color)
        if seat.remote != nil, let account = seat.player?.account?.name {
            Text(account)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The joining status of a ready seat's remote guest, or `nil` when the seat has none.
    func remoteStatus(_ seat: CouchSeat) -> (text: LocalizedStringResource, tone: CouchTone)? {
        guard case .ready = seat, let remote = seat.remote,
              let guest = kakusan?.state.guest(for: remote.guest) else {
            return nil
        }
        return guest.status
    }

    /// The Remember button for a ready seat whose remote guest can be remembered.
    @ViewBuilder
    func rememberAction(_ seat: CouchSeat) -> some View {
        if case .ready = seat, let remote = seat.remote, let kakusan,
           let guest = kakusan.state.guest(for: remote.guest),
           guest.canRemember {
            action(
                .kakusanPlayersRemember,
                symbol: "person.crop.circle.badge.checkmark",
                target: .remote(.remember(guest.id))
            ) {
                kakusan.send(.startRemembering(guest.id))
            }
        }
    }
}
