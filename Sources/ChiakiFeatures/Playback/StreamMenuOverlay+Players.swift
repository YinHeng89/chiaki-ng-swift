import SwiftUI
import MenuFocus

extension StreamMenuOverlay {
    /// Moves focus within the Players panel by its seat columns, remembering the last seat, or up
    /// to the tabs.
    func movePlayersFocus(_ control: StreamMenuControl, direction: MenuMoveDirection) {
        let destination = StreamPlayersNavigation.destination(
            from: control,
            direction: direction,
            controls: controls(in: .players),
            lastSeat: lastPlayerSeat
        )
        switch destination {
        case .control(let next):
            focusTarget = .control(next)
        case .tabs:
            focusTarget = .tab(panel)
        case .stay:
            break
        }
    }

    /// Cancels an in-progress controller pick in the Players panel.
    /// - Returns: `true` when a pick was cancelled and the Back or Exit press is consumed.
    func cancelPlayerPickingIfNeeded() -> Bool {
        guard panelPresented, panel == .players, couch?.picking != nil else {
            return false
        }
        couch?.send(.cancelPicking)
        return true
    }

    /// Closes the Invitations panel's friend picker on Back, returning focus to Invite friends.
    ///
    /// - Returns: Whether the picker was open.
    func closeInvitePickerIfNeeded() -> Bool {
        guard panelPresented, panel == .invitations, let invitations, invitations.invite != nil else {
            return false
        }
        invitations.send(.inviteClosed)
        focusTarget = .control(.invitationsInvite)
        return true
    }

    /// Records a new focus target so it can be restored later, along with its seat when it is a
    /// player control.
    func remember(_ target: StreamMenuFocusTarget?) {
        guard let target else {
            return
        }
        lastFocusTarget = target
        if case .control(let control) = target {
            let controls = controls(in: panel)
            if let index = controls.firstIndex(of: control),
               case .seat(let pad) = StreamPlayersNavigation.columns(of: controls)[index] {
                lastPlayerSeat = pad
            }
        }
    }

    /// On the next run loop, focuses the first control in a player's seat, used after a controller pick ends.
    func focusSeat(_ pad: UInt8) {
        Task { @MainActor in
            await Task.yield()
            guard panelPresented, panel == .players else {
                return
            }
            let controls = controls(in: .players)
            let columns = StreamPlayersNavigation.columns(of: controls)
            if let index = controls.indices.first(where: { columns[$0] == .seat(pad) }) {
                focusTarget = .control(controls[index])
            }
        }
    }

    /// Puts focus back on the remembered target, or a sensible fallback, after another presentation over the
    /// stream closes and left nothing focused.
    func restoreFocusAfterOtherPresentation() {
        guard navigationActive, focusTarget == nil else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard navigationActive, focusTarget == nil, !hasOtherPresentation else {
                return
            }
            focusTarget = restoredTarget
        }
    }

    private var restoredTarget: StreamMenuFocusTarget {
        switch lastFocusTarget {
        case .control(let control) where panelPresented && controls(in: panel).contains(control):
            return .control(control)
        case .tab(let item) where panelPresented:
            return .tab(item)
        case .measureDone where navigationLevel == .measuring:
            return .measureDone
        case .settings where panelPresented:
            return .settings
        case .log where panelPresented && liveLogButtonShown:
            return .log
        default:
            return .tab(panel)
        }
    }
}

/// Keeps the stream menu's focus continuous by remembering focus moves, refocusing a seat when its controller
/// pick ends and restoring focus when another presentation closes.
struct StreamMenuFocusContinuity: ViewModifier {
    /// The overlay whose focus this modifier tracks and restores.
    let overlay: StreamMenuOverlay

    /// Attaches the focus observers to the overlay's content.
    func body(content: Content) -> some View {
        content
            .onChange(of: overlay.focusTarget) { _, target in
                overlay.remember(target)
            }
            .onChange(of: overlay.couch?.picking) { previous, current in
                if let previous, current == nil {
                    overlay.focusSeat(previous)
                }
            }
            .onChange(of: overlay.hasOtherPresentation) { _, other in
                if !other {
                    overlay.restoreFocusAfterOtherPresentation()
                }
            }
    }
}
