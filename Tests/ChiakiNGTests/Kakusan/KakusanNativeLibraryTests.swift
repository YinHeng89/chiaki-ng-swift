#if CHIAKI_KAKUSAN
    import enum ChiakiBridge.chiaki_bridge
    import enum ChiakiBridge.libchiaking
    @testable import ChiakiClients
    @testable import ChiakiClientsLive
    import ChiakiCoreBridge
    import ChiakiModels
    @testable import ChiakiNG
    import ChiakiTestSupport
    import ComposableArchitecture
    import CryptoKit
    import Foundation
    import Testing
    import Video

    private let garbage = KakusanBlock(pasted: "RCP1:AAAA")!

    @MainActor @Test func anUnreadableInvitationIsNeverPreviewed() async throws {
        _ = try await TestComposition.scratch.accounts.storage()
        #expect(KakusanDevicesBridge().preview(garbage) == .failure(.invalidBlock))
        #expect(await KakusanClient.liveValue.preview(garbage) == .failure(.invalidBlock))
    }

    @MainActor @Suite(.serialized) struct KakusanNativePlayerTests {
        @Test func anIdlePlayerArmsButRefusesEveryHostCommand() throws {
            let player = try NativeStreamPlayer(inputs: TestComposition.scratch.input).native
            let configuration = KakusanHostConfiguration(capacity: 4, localSeats: 1)
            #expect(player.armKakusanHost(withCapacity: 5, localSeats: 1).decline() == .invalid_argument)
            #expect(player.armKakusanHost(withCapacity: 2, localSeats: 3).decline() == .invalid_argument)
            #expect(player.armKakusan(configuration) == .accepted)
            player.disarmKakusanHost()
            let guest = KakusanFixture.guest(1)
            let commands: [KakusanHostCommand] = [
                .enterCode(guest, KakusanFixture.code("1234")), .giveSeat(
                    guest,
                    preferred: 2,
                    controllerType: 6,
                    accountID: nil
                ), .remove(guest),
                .setLocalSeats(1),
                .setCapacity(4)
            ]
            for command in commands {
                #expect(player.sendKakusan(command) == .rejected(.internal))
            }
            #expect(player.inviteKakusanGuest().refusal() == .not_armed)
            #expect(player.importKakusanReply(KakusanFixture.reply.text).refusal() == .not_armed)
            #expect(player.kakusanGuestEnterCode("1234").refusal() == .not_armed)
        }

        @Test func eventHandlersInstallAndClear() throws {
            let player = try NativeStreamPlayer(inputs: TestComposition.scratch.input).native
            player.receiveKakusanEvents { _ in
            }
            #expect(player.kakusanEventHandler != nil)
            player.receiveKakusanEvents(nil)
            #expect(player.kakusanEventHandler == nil)
        }

        @Test func guestRunWithAnUnacceptableInvitationEndsThroughTheNativePath() async throws {
            _ = try await TestComposition.scratch.accounts.storage()
            let client = StreamSessionClient.live(
                leases: StreamLeases(),
                launcher: TestComposition.launcher()
            )
            let configuration = KakusanGuestConfiguration(invitation: garbage)
            let desk = KakusanGuestDesk()
            let events = withDependencies {
                $0.kakusanGuestDesk = desk
            } operation: {
                client.start(StreamSessionID(), .guest(configuration))
            }
            var guestEvents: [KakusanGuestEvent] = []
            var failure: StreamFailure?
            do {
                for try await event in events {
                    if case .guest(let guest) = event {
                        guestEvents.append(guest)
                    }
                }
            } catch let error as StreamFailure {
                failure = error
            }
            #expect(failure == .kakusan(.invalidBlock))
            #expect(guestEvents.isEmpty)
            #expect(desk.enterCode(KakusanFixture.code("1234")) == .rejected(.internal))
        }
    }
#endif
