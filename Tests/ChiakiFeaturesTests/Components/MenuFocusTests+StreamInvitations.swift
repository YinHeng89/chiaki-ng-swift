import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private struct InvitationsMenu {
        let menu: StoreOf<StreamMenuReducer>
        let invitations: StoreOf<CloudInvitationsFeature>
        let harness: MenuFocusHarness
        let override: KeyWindowOverride
    }

    @MainActor private func openInvitationsPanel(
        lists: LockIsolated<Int>,
        joins: LockIsolated<[String]>,
        invites: LockIsolated<[[String]]>
    ) async -> InvitationsMenu {
        let product = ProductID(rawValue: "EP0000-PPSA01234_00-GAME000000000000")!
        let dependencies = Self.invitationDependencies(
            Self.sampleInvitation,
            lists: lists,
            joins: joins,
            invites: invites
        )
        let menu = Store(initialState: StreamMenuReducer.State(context: .cloud("pscloud"))) {
            StreamMenuReducer()
        } withDependencies: {
            dependencies(&$0)
        }
        let invitations = Store(
            initialState: CloudInvitationsFeature.State(
                profile: ProfileID(uuid: UUID(0)),
                product: product
            )
        ) {
            CloudInvitationsFeature()
        } withDependencies: {
            dependencies(&$0)
        }
        let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: menu,
                stopTitle: "Disconnect",
                invitations: invitations
            ))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .invitations {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        await harness.pause(200)
        return InvitationsMenu(menu: menu, invitations: invitations, harness: harness, override: override)
    }

    @Test func invitationsAreJoinedAndRefreshedWithTheController() async {
        let joins = LockIsolated<[String]>([])
        let lists = LockIsolated(0)
        let opened = await openInvitationsPanel(lists: lists, joins: joins, invites: LockIsolated([]))
        let harness = opened.harness
        defer {
            opened.override.restore()
            harness.close()
        }
        #expect(opened.menu.navigation.panel == .invitations)
        #expect(lists.value == 1)
        await harness.send([.up, .up, .up, .confirm])
        await harness.pause(300)
        #expect(joins.value == [Self.sampleInvitation.id])
        await harness.send([.down, .confirm])
        await harness.pause(300)
        #expect(lists.value == 2)
        await harness.send([.down, .up, .confirm])
        await harness.pause(300)
        #expect(lists.value == 3)
        #expect(joins.value == [Self.sampleInvitation.id])
    }

    @Test func friendsArePickedAndInvitedWithTheController() async {
        let invites = LockIsolated<[[String]]>([])
        let opened = await openInvitationsPanel(
            lists: LockIsolated(0),
            joins: LockIsolated([]),
            invites: invites
        )
        let harness = opened.harness
        let invitations = opened.invitations
        defer {
            opened.override.restore()
            harness.close()
        }
        await harness.send([.up, .confirm])
        await harness.pause(300)
        #expect(invitations.invite != nil)
        await harness.send([.down, .down, .down, .confirm])
        await harness.pause(200)
        #expect(invitations.invite?.selected == ["222"])
        await harness.send([.up, .up, .confirm])
        await harness.pause(300)
        #expect(invites.value == [["222"]])
        await harness.send(.back)
        await harness.pause(300)
        #expect(invitations.invite == nil)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(invitations.invite != nil)
    }

    private static let sampleInvitation = CloudGameInvitation(
        id: "11111111-2222-3333-4444-555555555555",
        invitationID: "inv-1111",
        inviter: "Friend",
        sessionName: "Squad",
        titleIDs: ["PPSA01234_00"],
        sent: nil,
        unread: true,
        players: 1,
        maxPlayers: 4,
        joining: .joinable
    )

    private static func invitationDependencies(
        _ invitation: CloudGameInvitation,
        lists: LockIsolated<Int>,
        joins: LockIsolated<[String]>,
        invites: LockIsolated<[[String]]>
    ) -> @Sendable (inout DependencyValues) -> Void {
        {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080)
            }
            $0.streamSession.saveTuning = { _, _ in
            }
            $0.streamSession.invitations = { _ throws(CloudInvitationFailure) in
                lists.withValue {
                    $0 += 1
                }
                return [invitation]
            }
            $0.streamSession.joinOnCloud = { _, session throws(CloudInvitationFailure) in
                joins.withValue {
                    $0.append(session)
                }
                throw .rejected
            }
            $0.streamSession.friends = { _ throws(CloudInvitationFailure) in
                [
                    PSNFriend(id: "222", onlineID: "Friend", online: true, playing: "Astro"),
                    PSNFriend(id: "333", onlineID: "Away")
                ]
            }
            $0.streamSession.ownGameSession = { _, title, _ throws(CloudInvitationFailure) in
                #expect(title == "PPSA01234_00")
                return OwnGameSession(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", players: 1, maxPlayers: 4,
                                      openToAnyone: true)
            }
            $0.streamSession.inviteFriends = { _, target, friends throws(CloudInvitationFailure) in
                #expect(target == .game("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
                invites.withValue {
                    $0.append(friends)
                }
            }
        }
    }
}
