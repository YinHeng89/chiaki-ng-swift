#if CHIAKI_KAKUSAN
    import enum ChiakiBridge.chiaki_bridge
    import enum ChiakiBridge.libchiaking
    @testable import ChiakiClients
    @testable import ChiakiClientsLive
    import ChiakiCoreBridge
    import ChiakiModels
    @testable import ChiakiNG
    import ComposableArchitecture
    import Foundation
    import Testing
    import Video

    private enum KakusanLive {
        static let environment = ProcessInfo.processInfo.environment
        static let enabled = environment["CHIAKI_KAKUSAN_LIVE"] == "1"
        static let connected: Set<KakusanSessionState> = [
            .connecting,
            .verifying,
            .admitting,
            .readyWait,
            .active
        ]

        static var paired: Bool {
            enabled && environment["CHIAKI_KAKUSAN_HOST_CODE"] != nil
                && environment["CHIAKI_KAKUSAN_GUEST_CODE"] != nil
        }

        static func write(_ text: String, to path: String) {
            FileManager.default.createFile(
                atPath: path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]
            )
        }

        static func hostCode(at path: String) -> KakusanCode? {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }
            return KakusanCode(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        static var waitSeconds: Int {
            environment["CHIAKI_KAKUSAN_LIVE_WAIT"].flatMap(Int.init) ?? 180
        }

        static func expectReachedHost(_ events: [KakusanGuestEvent]) {
            #expect(events.contains {
                if case .replyReady = $0 {
                    return true
                }
                return false
            })
            #expect(events.contains {
                if case .stateChanged(let change) = $0 {
                    return connected.contains(change.state)
                }
                return false
            })
        }

        static func writeReply(_ reply: KakusanBlock, to path: String) {
            FileManager.default.createFile(
                atPath: path, contents: Data(reply.text.utf8), attributes: [.posixPermissions: 0o600]
            )
        }
    }

    @MainActor @Test(
        .enabled(if: KakusanLive.enabled, "Needs a hosting Mac; set CHIAKI_KAKUSAN_LIVE=1"),
        .timeLimit(.minutes(10))
    )
    func liveGuestAcceptsARealInvitationAndReachesTheHost() async throws {
        let invitationPath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_INVITATION"])
        let replyPath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_REPLY"])
        let invitation = try #require(KakusanBlock(pasted: String(
            contentsOfFile: invitationPath,
            encoding: .utf8
        )))
        let preview = try KakusanDevicesBridge().preview(invitation).get()
        #expect(preview.expiresAt > Date())
        let client = StreamSessionClient.live(leases: StreamLeases(), launcher: TestComposition.launcher())
        let id = StreamSessionID()
        let deadline = Task {
            try await Task.sleep(for: .seconds(KakusanLive.waitSeconds))
            _ = await client.leave(id, .disconnect)
        }
        defer {
            deadline.cancel()
        }
        let configuration = KakusanGuestConfiguration(invitation: invitation)
        var received: [KakusanGuestEvent] = []
        for try await event in client.start(id, .guest(configuration)) {
            guard case .guest(let event) = event else {
                continue
            }
            received.append(event)
            switch event {
            case .replyReady(let reply):
                KakusanLive.writeReply(reply, to: replyPath)
            case .stateChanged(let change) where KakusanLive.connected.contains(change.state):
                _ = await client.leave(id, .disconnect)
            default:
                break
            }
        }
        KakusanLive.expectReachedHost(received)
    }

    @MainActor @Test(
        .enabled(if: KakusanLive.paired, "Needs a hosting peer that exchanges codes through files"),
        .timeLimit(.minutes(10))
    )
    func liveGuestPairsAndReachesTheStream() async throws {
        let invitationPath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_INVITATION"])
        let replyPath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_REPLY"])
        let hostCodePath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_HOST_CODE"])
        let guestCodePath = try #require(KakusanLive.environment["CHIAKI_KAKUSAN_GUEST_CODE"])
        let invitation = try #require(KakusanBlock(pasted: String(
            contentsOfFile: invitationPath,
            encoding: .utf8
        )))
        let client = StreamSessionClient.live(leases: StreamLeases(), launcher: TestComposition.launcher())
        let id = StreamSessionID()
        let deadline = Task {
            try await Task.sleep(for: .seconds(KakusanLive.waitSeconds))
            _ = await client.leave(id, .disconnect)
        }
        let desk = KakusanGuestDesk()
        let codes = acceptHostCodes(at: hostCodePath, through: desk)
        defer {
            deadline.cancel()
            codes.cancel()
        }
        let configuration = KakusanGuestConfiguration(invitation: invitation)
        let events = withDependencies {
            $0.kakusanGuestDesk = desk
        } operation: {
            client.start(id, .guest(configuration))
        }
        var received: [KakusanGuestEvent] = []
        for try await event in events {
            guard case .guest(let event) = event else {
                continue
            }
            received.append(event)
            await respond(to: event, replyPath: replyPath, guestCodePath: guestCodePath) {
                _ = await client.leave(id, .disconnect)
            }
        }
        expectActiveStream(received)
    }

    @MainActor private func acceptHostCodes(at path: String,
                                            through desk: KakusanGuestDesk) -> Task<Void, any Error> {
        Task { @MainActor in
            while !Task.isCancelled {
                if let code = KakusanLive.hostCode(at: path),
                   case .accepted = desk.enterCode(code) {
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    @MainActor private func respond(
        to event: KakusanGuestEvent,
        replyPath: String,
        guestCodePath: String,
        stop: () async -> Void
    ) async {
        switch event {
        case .replyReady(let reply):
            KakusanLive.writeReply(reply, to: replyPath)
        case .codeReady(let code):
            KakusanLive.write(code.digits, to: guestCodePath)
        case .streamReady:
            try? await Task.sleep(for: .seconds(2))
            await stop()
        default:
            break
        }
    }

    private func expectActiveStream(_ events: [KakusanGuestEvent]) {
        #expect(events.contains {
            if case .stateChanged(let change) = $0 {
                return change.state == .active
            }
            return false
        })
        #expect(events.contains {
            if case .streamReady(let fps) = $0 {
                return fps == 60
            }
            return false
        })
    }
#endif
