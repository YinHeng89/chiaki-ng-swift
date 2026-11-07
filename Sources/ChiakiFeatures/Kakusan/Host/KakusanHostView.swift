import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The host's cards over the console stream: one guest's invitation card, or naming a guest's device.
struct KakusanHostView: View {
    /// The host.
    let store: StoreOf<KakusanHostFeature>

    var body: some View {
        ZStack {
            if let invite = store.scope(state: \.destination?.invite, action: \.destination.invite),
               let guest = store.guests[id: invite.guest],
               KakusanInviteControls.shows(guest.attempt.phase) {
                KakusanInviteCard(store: invite, guest: guest, host: store.state)
                    .id(guest.id)
            }
            if let remember = store.scope(state: \.destination?.remember, action: \.destination.remember) {
                KakusanRememberCard(store: remember, title: .kakusanRememberDeviceTitle)
            }
        }
    }
}
