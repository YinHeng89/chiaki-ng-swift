@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

private final class PanelCloses: @unchecked Sendable {
    var count = 0
}

private func panelState() -> PSNAlertsFeature.State {
    var state = PSNAlertsFeature.State()
    state.items = [
        PSNAlertsFeature.Item(
            id: "invitation:s-1",
            kind: .invitation(CloudGameInvitation(
                id: "s-1",
                inviter: "Friend",
                sessionName: "Lobby",
                titleIDs: ["PPSA01234_00"],
                sent: nil,
                unread: true,
                players: 1,
                maxPlayers: 4,
                joining: .joinable
            )),
            arrived: Date(timeIntervalSince1970: 0)
        )
    ]
    return state
}

private struct PartyPanel {
    let store: StoreOf<PSNAlertsFeature>
    let consoles: [PSNAlertsFeature.PartyConsole]
    let asked: LockIsolated<[HardwareID?]>
}

@MainActor private func partyPanel() -> PartyPanel {
    var state = PSNAlertsFeature.State()
    state.items = [
        PSNAlertsFeature.Item(
            id: "party:p-1",
            kind: .party(PSNPartyAlert(sender: "Host", sessionID: "p-1")),
            arrived: Date(timeIntervalSince1970: 0)
        )
    ]
    state.watch = .watching(ProfileID(uuid: UUID(1)), UUID(0))
    let asked = LockIsolated<[HardwareID?]>([])
    let store = Store(initialState: state) {
        PSNAlertsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory()
        $0.platform.notificationPermission = {
            .allowed
        }
        $0.streamSession.joinParty = { _, _, console throws(CloudInvitationFailure) in
            asked.withValue {
                $0.append(console)
            }
        }
    }
    store.send(.settings(.appeared))
    let consoles = [
        PSNAlertsFeature.PartyConsole(hardwareID: HardwareID(hex: "0123456789ab")!, name: "Den"),
        PSNAlertsFeature.PartyConsole(hardwareID: HardwareID(hex: "ba9876543210")!, name: "Attic")
    ]
    return PartyPanel(store: store, consoles: consoles, asked: asked)
}

extension MenuFocusTests {
    @Test func theNotificationsPanelStartsOnRefreshWalksDownAndBackCloses() async {
        let store = Store(initialState: panelState()) {
            PSNAlertsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.settings = .inMemory()
            $0.platform.notificationPermission = {
                .allowed
            }
        }
        store.send(.settings(.appeared))
        let closes = PanelCloses()
        let harness = MenuFocusHarness(width: 600, height: 700) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(store: store) {
                closes.count += 1
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        let refresh = harness.focusedFrame
        await harness.send(.down)
        let messagesRow = harness.focusedFrame
        #expect(messagesRow != refresh)
        #expect(messagesRow.maxY < refresh.minY)
        await harness.send(.down)
        let mute = harness.focusedFrame
        #expect(mute != refresh)
        await harness.send(.down)
        let invitations = harness.focusedFrame
        #expect(invitations.maxY < mute.minY)
        await harness.send(.confirm)
        await waitUntil(harness) {
            !store.alertSettings.invitations
        }
        #expect(!store.alertSettings.invitations)
        await harness.send(.down)
        #expect(harness.focusedFrame.maxY < invitations.minY)
        await harness.send(.up)
        await harness.send(.up)
        await harness.send(.up)
        #expect(harness.focusedFrame == messagesRow)
        await harness.send(.up)
        #expect(harness.focusedFrame == refresh)
        await harness.send(.up)
        #expect(harness.focusedFrame == refresh)
        await harness.send(.back)
        await waitUntil(harness) {
            closes.count == 1
        }
        #expect(closes.count == 1)
    }

    @Test func aPartysJoinButtonsFollowItsMuteButtonAndJoinOnTheChosenConsole() async {
        let panel = partyPanel()
        let store = panel.store
        let consoles = panel.consoles
        let asked = panel.asked
        let attic = consoles[1].hardwareID
        let closes = PanelCloses()
        let harness = MenuFocusHarness(width: 600, height: 700) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(store: store, consoles: consoles) {
                closes.count += 1
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        let refresh = harness.focusedFrame
        await harness.send([.down, .down])
        let mute = harness.focusedFrame
        #expect(mute != refresh)
        await harness.send(.down)
        let joinDen = harness.focusedFrame
        #expect(joinDen.maxY < mute.minY)
        await harness.send(.right)
        let joinAttic = harness.focusedFrame
        #expect(joinAttic.minX > joinDen.maxX)
        await harness.send(.right)
        #expect(harness.focusedFrame == joinAttic)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.homeJoin == .joined(session: "p-1", console: attic)
        }
        #expect(asked.value == [attic])
        await harness.pause(100)
        let joinedAttic = harness.focusedFrame
        await harness.send(.left)
        let joinedDen = harness.focusedFrame
        #expect(joinedDen.maxX < joinedAttic.minX)
        #expect(joinedDen.midY == joinedAttic.midY)
        await harness.send(.down)
        let invitations = harness.focusedFrame
        #expect(invitations != joinedDen)
        await harness.send(.up)
        #expect(harness.focusedFrame == joinedDen)
        await harness.send(.up)
        #expect(harness.focusedFrame.minX == mute.minX)
        #expect(harness.focusedFrame.minY > joinedDen.maxY)
        await harness.send([.up, .up])
        let top = harness.focusedFrame
        #expect(top.minX == refresh.minX)
        #expect(top.size == refresh.size)
        await harness.send(.up)
        #expect(harness.focusedFrame == top)
        await harness.send(.back)
        await waitUntil(harness) {
            closes.count == 1
        }
        #expect(closes.count == 1)
    }
}

private let cloudMarker = HardwareID(hex: "ffffffffffff")!

@MainActor private func gameInvitationPanel(
    session: String,
    joins: LockIsolated<[String]>,
    plays: LockIsolated<[HardwareID]>
) -> StoreOf<PSNAlertsFeature> {
    var state = PSNAlertsFeature.State()
    state.items = [
        PSNAlertsFeature.Item(
            id: "invitation:\(session)",
            kind: .invitation(CloudGameInvitation(
                id: session,
                inviter: "Friend",
                sessionName: "Lobby",
                titleIDs: ["PPSA01234_00"],
                sent: nil,
                unread: true,
                players: 1,
                maxPlayers: 4,
                joining: .joinable
            )),
            arrived: Date(timeIntervalSince1970: 0)
        )
    ]
    state.watch = .watching(ProfileID(uuid: UUID(1)), UUID(0))
    let store = Store(initialState: state) {
        PSNAlertsFeature()
        Reduce { _, action in
            if case .delegate(.playOn(let console)) = action {
                plays.withValue {
                    $0.append(console)
                }
            }
            if case .delegate(.playInCloud) = action {
                plays.withValue {
                    $0.append(cloudMarker)
                }
            }
            return .none
        }
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory()
        $0.platform.notificationPermission = {
            .allowed
        }
        $0.streamSession.joinOn = { _, joined, _ throws(CloudInvitationFailure) in
            joins.withValue {
                $0.append(joined)
            }
        }
    }
    store.send(.settings(.appeared))
    return store
}

extension MenuFocusTests {
    @Test func aGameInvitationJoinsOnAPS5AndThenOffersPlay() async {
        let session = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let den = HardwareID(hex: "0123456789ab")!
        let joins = LockIsolated<[String]>([])
        let plays = LockIsolated<[HardwareID]>([])
        let store = gameInvitationPanel(session: session, joins: joins, plays: plays)
        let consoles = [PSNAlertsFeature.PartyConsole(hardwareID: den, name: "Den")]
        let harness = MenuFocusHarness(width: 600, height: 760) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(store: store, consoles: consoles) {
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        await harness.send([.down, .down, .down, .confirm])
        await waitUntil(harness) {
            store.homeJoin == .joined(session: session, console: den)
        }
        #expect(joins.value == [session])
        await harness.pause(200)
        await harness.send([.down, .confirm])
        await waitUntil(harness) {
            plays.value == [den]
        }
        #expect(plays.value == [den])
    }
}

extension MenuFocusTests {
    @Test func aGameInvitationIsPlayedInTheCloudWithTheController() async {
        let session = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let plays = LockIsolated<[HardwareID]>([])
        let store = gameInvitationPanel(session: session, joins: LockIsolated([]), plays: plays)
        let consoles = [PSNAlertsFeature.PartyConsole(
            hardwareID: HardwareID(hex: "0123456789ab")!,
            name: "Den"
        )]
        let harness = MenuFocusHarness(width: 600, height: 760) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(
                store: store,
                consoles: consoles,
                cloudPlayable: ["invitation:\(session)"]
            ) {
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        await harness.send([.down, .down, .down, .down, .confirm])
        await waitUntil(harness) {
            plays.value == [cloudMarker]
        }
        #expect(plays.value == [cloudMarker])
    }
}
