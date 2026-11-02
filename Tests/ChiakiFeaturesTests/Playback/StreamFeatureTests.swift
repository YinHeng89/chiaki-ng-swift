import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let account = UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!
private let consoleID = UUID(uuidString: "00000000-0000-0000-0000-00000000BBBB")!
private let console = RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5, id: consoleID)
private let firstSession = StreamSessionID(uuid: UUID(0))
private let progressReportedAt = Date(timeIntervalSince1970: 2000)

private let launchOffer = CloudDatacenterLaunchOffer(
    entries: [
        CloudDatacenterLaunchOffer.Entry(name: "us-east-1", rttMs: 34),
        CloudDatacenterLaunchOffer.Entry(name: "eu-west-1", rttMs: 91)
    ],
    timeoutSeconds: 3
)

private func cloudSource() -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: account),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
            name: "Game",
            service: .psCloud
        )
    ))
}

@MainActor @Test func aConsoleStreamReportsItsStartAndFirstFrameToItsParent() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.receive(.delegate(.started(firstSession)))
    #expect(store.state.status == .connecting)
    #expect(store.state.target == StreamTarget(account: account, consoleID: consoleID, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.receive(.delegate(.playing(firstSession)))
    #expect(store.state.status == .playing)
    #expect(calls.started.value == [firstSession])
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    await store.receive(.delegate(.ended(firstSession)))
    #expect(store.state.status == .idle)
    #expect(calls.left.value == [firstSession])
}

@MainActor @Test func aStoppedSessionsLateCompletionsCannotMoveTheNextOne() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.ended(firstSession))
    await store.send(.failed(firstSession, .renderer))
    await store.send(.deadlineElapsed(firstSession, .startAttempt(0)))
    #expect(store.state.status == .idle)
    #expect(store.state.session == .ended(firstSession, .left(.left)))
}

@MainActor @Test func eventsFromAnotherSessionNeverReachTheLiveOne() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    let other = StreamSessionID(uuid: UUID(99))
    await store.send(.event(other, .firstFrame))
    await store.send(.event(other, .displayProhibited(true)))
    #expect(store.state.status == .connecting)
    #expect(!store.state.displayProhibited)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aSecondStartWaitsUntilTheFirstSessionHasStopped() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.startConsole(account: account, console: console, route: .remote))
    #expect(calls.started.value == [firstSession])
    #expect(store.state.target?.route == .local)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aRejectedPairingOffersUnpairAndThenAsksToPairAgain() async {
    let calls = StreamSessionCalls()
    let unpaired = LockIsolated<[UUID]>([])
    let store = calls.store(failure: .stream(.startFailed(.pairingRejected), overInternet: false)) {
        $0.consoles.unpair = { profile, _ in
            unpaired.withValue {
                $0.append(profile)
            }
            return .success(())
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.receive(.failed(firstSession, .stream(.startFailed(.pairingRejected), overInternet: false)))
    #expect(store.state.status == .failed)
    #expect(store.state.unpair == UnpairOffer(account: account, console: console))
    await store.send(.view(.unpair))
    await store.receive(.unpaired(firstSession))
    await store.receive(.delegate(.pairAgain(console)))
    #expect(unpaired.value == [account])
    #expect(store.state.status == .idle)
}

@MainActor @Test func aRefusedUnpairKeepsTheOfferForAnotherTry() async {
    let calls = StreamSessionCalls()
    let store = calls.store(failure: .stream(.startFailed(.pairingRejected), overInternet: false)) {
        $0.consoles.unpair = { _, _ in
            .failure(.unavailable)
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.receive(.failed(firstSession, .stream(.startFailed(.pairingRejected), overInternet: false)))
    await store.send(.view(.unpair))
    await store.receive(.unpairFailed(firstSession))
    #expect(store.state.unpair?.phase == .refused)
    await store.send(.dismissFailure)
    #expect(store.state.status == .idle)
    #expect(store.state.unpair == nil)
}

@MainActor @Test func theStartupDeadlineFailsTheSessionAndCannotBeResurrected() async {
    let calls = StreamSessionCalls()
    let clock = TestClock()
    let store = calls.store(clock: clock)
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.receive(.delegate(.started(firstSession)))
    await clock.advance(by: StreamDeadline.startAttempt(0).duration)
    await store.receive(.deadlineElapsed(firstSession, .startAttempt(0)))
    #expect(store.state.session.failure == .timedOut(.startAttempt(0)))
    await store.send(.event(firstSession, .firstFrame))
    #expect(store.state.status == .failed)
}

@MainActor @Test func theStartupDeadlinePausesWhileTheLoginPINPromptIsOpen() async {
    let calls = StreamSessionCalls()
    let clock = TestClock()
    let store = calls.store(clock: clock)
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .accessRequested(.loginPIN(retry: false))))
    await store.receive(.savedLoginPINMissing(UUID(1)))
    #expect(store.state.access == .requested(.loginPIN(retry: false)))
    await clock.advance(by: .seconds(120))
    #expect(store.state.status == .connecting)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aSavedLoginPINIsSentWithoutShowingThePrompt() async {
    let calls = StreamSessionCalls()
    let saved = StreamAccessCode("1234")!
    let store = calls.store {
        $0.consoles.loginPIN = { _ in
            saved
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .accessRequested(.loginPIN(retry: false))))
    #expect(store.state.access == .recalling(UUID(1)))
    await store.receive(.savedLoginPINSubmitted(UUID(1), true))
    #expect(calls.codes.value == [saved])
    #expect(store.state.access.loginPINOpen == false)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aRejectedSavedLoginPINIsForgottenAndTheUserIsAsked() async {
    let calls = StreamSessionCalls()
    let cleared = LockIsolated(0)
    let store = calls.store {
        $0.consoles.loginPIN = { _ in
            StreamAccessCode("1234")
        }
        $0.consoles.clearLoginPIN = { _ in
            cleared.withValue {
                $0 += 1
            }
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .accessRequested(.loginPIN(retry: false))))
    await store.receive(.savedLoginPINSubmitted(UUID(1), true))
    await store.send(.event(firstSession, .accessRequested(.loginPIN(retry: true))))
    #expect(store.state.access == .requested(.loginPIN(retry: true)))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    #expect(cleared.value == 1)
}

@MainActor @Test func aReconnectShowsAndThenRestoresSeatsAndMicrophone() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .reconnecting(attempt: 1)))
    #expect(store.state.session.reconnectAttempt == nil)
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .reconnecting(attempt: 1)))
    await store.receive(.couch(.sessionReconnecting))
    #expect(store.state.session.reconnectAttempt == 1)
    #expect(store.state.status == .playing)
    await store.send(.event(firstSession, .reconnected))
    await store.receive(.couch(.sessionReconnected))
    await store.receive(.microphone(.streamReconnected))
    #expect(store.state.session.reconnectAttempt == nil)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aSilentConnectionWaitsUntilHeardAgainOrAReconnectStarts() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .connectionWaiting(true)))
    #expect(store.state.connection == .waiting)
    await store.send(.event(firstSession, .connectionWaiting(false)))
    #expect(store.state.connection == .receiving)
    await store.send(.event(firstSession, .connectionWaiting(true)))
    await store.send(.event(firstSession, .reconnecting(attempt: 1)))
    await store.receive(.couch(.sessionReconnecting))
    #expect(store.state.connection == .receiving)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func theConsoleKeyboardSendsItsCommandsToTheLiveSession() async throws {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .keyboard(.opened("hi"))))
    let opened = try #require(store.state.keyboard.session)
    #expect(opened.text == "hi")
    await store.send(.view(.keyboardEdited(opened.id, "hello")))
    await store.send(.view(.keyboardFinished(opened.id, accepted: true)))
    await store.finish(timeout: .seconds(1))
    #expect(calls.keyboard.value.contains(.accept("hello")))
    #expect(store.state.keyboard.session == nil)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aRestRequestTheConsoleRefusedShowsTheRestNotice() async {
    let calls = StreamSessionCalls()
    let clock = TestClock()
    let store = calls.store(outcome: .restRefused, clock: clock)
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.leave(.restMode))
    await store.receive(.stopped(firstSession, .restRefused))
    #expect(store.state.restNotice != .hidden)
    await clock.advance(by: StreamFeature.restNoticeDuration)
    await store.receive(\.restNoticeExpired)
    #expect(store.state.restNotice == .hidden)
}

@MainActor @Test func theCloudDatacenterChoiceCountsDownAndExpiresIntoTheAutomaticChoice() async {
    let calls = StreamSessionCalls()
    let clock = TestClock()
    let store = calls.store(clock: clock)
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .cloudStep(.findingServer)))
    await store.send(.event(firstSession, .datacenterOffered(launchOffer)))
    #expect(store.state.session.stage?.datacenterChoice?.offer == launchOffer)
    await clock.advance(by: .seconds(3))
    await store.receive(.datacenterTick(firstSession))
    await store.receive(.datacenterTick(firstSession))
    await store.receive(.datacenterTick(firstSession))
    #expect(store.state.session.stage?.datacenterChoice == .expired)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func choosingACloudDatacenterSendsItThroughTheSession() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .cloudStep(.findingServer)))
    await store.send(.event(firstSession, .datacenterOffered(launchOffer)))
    await store.send(.view(.chooseDatacenter("eu-west-1")))
    await store.receive(.datacenterSent(firstSession, "eu-west-1", accepted: true))
    #expect(calls.datacenters.value == ["eu-west-1"])
    #expect(store.state.session.stage?.datacenterChoice == .sent(name: "eu-west-1"))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aFailedCloudStreamStartsAgainAsANewSession() async {
    let calls = StreamSessionCalls()
    let store = calls.store(failure: .serviceRefused("busy"))
    await store.send(.start(cloudSource()))
    await store.receive(.failed(firstSession, .serviceRefused("busy")))
    #expect(store.state.status == .failed)
    await store.send(.retry)
    #expect(calls.started.value.count == 2)
    #expect(calls.started.value.first == firstSession)
    #expect(store.state.session.id != firstSession)
}

@MainActor @Test func aCloudStreamEndingBeforeItsFirstFrameIsAFailure() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource()))
    await store.send(.ended(firstSession))
    #expect(store.state.session.failure == .stream(.finished, overInternet: true))
}

@MainActor @Test func theWindowGoesFullScreenWithTheFirstFrameAndIsRestoredWhenTheStreamEnds() async {
    let calls = StreamSessionCalls()
    let window = LockIsolated<[String]>([])
    let store = calls.store {
        $0.platform.enterFullScreen = {
            window.withValue {
                $0.append("full")
            }
        }
        $0.platform.restoreWindow = {
            window.withValue {
                $0.append("restore")
            }
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    await store.finish(timeout: .seconds(1))
    #expect(window.value == ["full", "restore"])
}

@MainActor @Test func aLaunchThatOwnsTheWindowKeepsItsSize() async {
    let calls = StreamSessionCalls()
    let window = LockIsolated<[String]>([])
    var launching = StreamFeature.State()
    launching.windowOwner = .launch
    let store = calls.store(initial: launching) {
        $0.platform.enterFullScreen = {
            window.withValue {
                $0.append("full")
            }
        }
        $0.platform.restoreWindow = {
            window.withValue {
                $0.append("restore")
            }
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    #expect(window.value.isEmpty)
}

@MainActor @Test func theStreamMenuFollowsThePictureRouteThePlayerApplied() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .pictureRoute(.remote)))
    #expect(store.state.menu.context == .console(.remote, ps5: true))
    #expect(store.state.menu.session == firstSession)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aCloudLaunchCarriesItsBandwidthAndDatacenterToTheStreamMenu() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let selection = CloudDatacenterSelection(name: "us-east-1", rttMs: 34, automatic: false)
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .datacenterSelected(selection)))
    #expect(store.state.datacenter == selection)
    #expect(store.state.menu.datacenter == selection)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aConsoleStartShowsItsProgressUntilTheFirstFrame() async {
    let calls = StreamSessionCalls()
    let store = calls.store {
        $0.date = .constant(progressReportedAt)
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(
        StreamSessionID(uuid: UUID(99)),
        .progress(StreamProgress(detail: streamRetryWait))
    ))
    #expect(store.state.progress == nil)
    await store.send(.event(firstSession, .progress(StreamProgress(detail: streamRetryWait))))
    #expect(store.state.progress == TimedProgress(streamRetryWait, at: progressReportedAt))
    await store.send(.event(firstSession, .firstFrame))
    #expect(store.state.progress == nil)
    await store.send(.event(firstSession, .progress(StreamProgress(detail: streamRetryWait))))
    #expect(store.state.progress == nil)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aReconnectShowsItsProgressUntilTheSessionIsBack() async {
    let calls = StreamSessionCalls()
    let store = calls.store {
        $0.date = .constant(progressReportedAt)
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .reconnecting(attempt: 1)))
    await store.send(.event(
        firstSession,
        .progress(StreamProgress(reconnecting: true, detail: streamReconnectWait))
    ))
    #expect(store.state.progress == TimedProgress(streamReconnectWait, at: progressReportedAt))
    await store.send(.event(firstSession, .reconnected))
    #expect(store.state.progress == nil)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aLateUnpairAnswerFromAnEarlierFailureCannotSettleTheNextOffer() async throws {
    let calls = StreamSessionCalls()
    let rejected = StreamFailure.stream(.startFailed(.pairingRejected), overInternet: false)
    let first = AsyncStream.makeStream(of: Result<Void, PairingFailure>.self)
    let second = AsyncStream.makeStream(of: Result<Void, PairingFailure>.self)
    let unpairs = LockIsolated(0)
    let store = calls.store(failure: rejected) {
        $0.consoles.unpair = { _, _ in
            let call = unpairs.withValue {
                $0 += 1
                return $0
            }
            let answers = call == 1
                ? first.stream
                : second.stream
            for await answer in answers {
                return answer
            }
            return .failure(.unavailable)
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.receive(.failed(firstSession, rejected))
    await store.send(.view(.unpair))
    while unpairs.value < 1 {
        await Task.yield()
    }
    await store.send(.dismissFailure)
    await store.send(.startConsole(account: account, console: console, route: .local))
    let next = try #require(store.state.session.id)
    #expect(next != firstSession)
    await store.receive(.failed(next, rejected))
    await store.send(.view(.unpair))
    while unpairs.value < 2 {
        await Task.yield()
    }
    #expect(store.state.unpair?.phase == .unpairing)
    first.continuation.yield(.failure(.unavailable))
    await store.receive(.unpairFailed(firstSession))
    #expect(store.state.unpair?.phase == .unpairing)
    second.continuation.yield(.success(()))
    await store.receive(.unpaired(next))
    await store.receive(.delegate(.pairAgain(console)))
    #expect(store.state.status == .idle)
}

private let couchGuest = ControllerDevice(
    id: 9, preferenceKey: "unit:9", name: "DualShock 4", transport: "USB", individual: true,
    rumble: true, lights: true, motion: true, touchpad: true
)

private let nextCouchGuest = ControllerDevice(
    id: 12, preferenceKey: "unit:12", name: "DualSense Wireless Controller", transport: "USB",
    individual: true, rumble: true, lights: true, motion: true, touchpad: true
)

@MainActor @Test func aReseatLeftOverFromAnEndedSessionNeverSeatsItsPlayersInTheNextOne() async throws {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.couch(.event(.controllerClaimed(couchGuest))))
    #expect(store.state.couch.seats[1].device == couchGuest)
    await store.send(.event(firstSession, .reconnecting(attempt: 1)))
    await store.receive(.couch(.sessionReconnecting))
    await store.send(.event(firstSession, .reconnected))
    await store.receive(.couch(.sessionReconnected))
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
    await store.skipReceivedActions()
    #expect(!store.state.couch.active)
    await store.send(.start(cloudSource()))
    let next = try #require(store.state.session.id)
    #expect(next != firstSession)
    await store.send(.event(next, .firstFrame))
    await store.send(.couch(.event(.controllerClaimed(nextCouchGuest))))
    #expect(store.state.couch.seats[1].device == nextCouchGuest)
    await store.send(.couch(.event(.dropped(pad: 1))))
    #expect(store.state.couch.seats[1] == .open)
    #expect(store.state.couch.seats[1].device != couchGuest)
    await store.send(.event(next, .reconnecting(attempt: 1)))
    await store.receive(.couch(.sessionReconnecting))
    #expect(store.state.couch.reseat.values.allSatisfy { $0.device != couchGuest })
    await store.send(.stop)
    await store.receive(.stopped(next, .left))
}
