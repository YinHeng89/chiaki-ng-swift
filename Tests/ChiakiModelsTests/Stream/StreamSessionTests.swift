import ChiakiModels
import Foundation
import Testing

private let first = StreamSessionID(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
private let second = StreamSessionID(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

private let console = StreamSource.console(
    ConsoleStreamTarget(profile: ProfileID(), console: ConsoleID(), address: "192.168.1.2", kind: .ps5),
    route: .home
)

private let cloud = StreamSource.cloud(CloudStreamRequest(
    profile: ProfileID(),
    title: CloudStreamTitle(product: ProductID(rawValue: "EP0001")!, name: "Game", service: .psCloud)
))

private let offer = CloudDatacenterLaunchOffer(
    entries: [.init(name: "Tokyo", rttMs: 20), .init(name: "Osaka", rttMs: 30)],
    timeoutSeconds: 2
)

@Test func streamSessionStartsAConsoleAtTheFirstAttempt() {
    var session = StreamSession.idle
    let moved1 = session.begin(first, source: console)
    #expect(moved1)
    #expect(session == .starting(first, .connecting(attempt: 0)))
    #expect(session.liveID == first)
    let moved2 = session.begin(second, source: console)
    #expect(!moved2)
}

@Test func streamSessionStartsACloudTitleAtTheCheckingStep() {
    var session = StreamSession.idle
    session.begin(first, source: cloud)
    #expect(session == .starting(first, .cloud(.checking)))
}

@Test func streamSessionCountsConsoleRetriesInOrderOnly() {
    var session = StreamSession.idle
    session.begin(first, source: console)
    let moved3 = session.updateStage(for: first) { stage in stage.retried(2) }
    #expect(!moved3)
    let moved4 = session.updateStage(for: first) { stage in stage.retried(1) }
    #expect(moved4)
    let moved5 = session.updateStage(for: first) { stage in stage.retried(1) }
    #expect(!moved5)
    let moved6 = session.updateStage(for: second) { stage in stage.retried(2) }
    #expect(!moved6)
    #expect(session.stage == .connecting(attempt: 1))
}

@Test func streamSessionMovesCloudStepsForwardOnly() {
    var session = StreamSession.idle
    session.begin(first, source: cloud)
    let moved7 = session.updateStage(for: first) { stage in stage.advance(to: .findingServer) }
    #expect(moved7)
    let moved8 = session.updateStage(for: first) { stage in stage.advance(to: .preparing) }
    #expect(!moved8)
    let moved9 = session.updateStage(for: second) { stage in stage.advance(to: .connecting) }
    #expect(!moved9)
    #expect(session.stage?.cloudStep == .findingServer)
}

@Test func streamSessionQueuePositionIsAStartingWaitThatEndsWithTheStep() {
    var session = StreamSession.idle
    session.begin(first, source: cloud)
    session.updateStage(for: first) { stage in stage.advance(to: .preparing) }
    let moved10 = session.updateStage(for: first) { stage in stage.queue(at: 12) }
    #expect(moved10)
    #expect(session.stage?.queuePosition == 12)
    let moved11 = session.updateStage(for: first) { stage in stage.queue(at: 12) }
    #expect(!moved11)
    let moved12 = session.updateStage(for: first) { stage in stage.queue(at: 4) }
    #expect(moved12)
    session.updateStage(for: first) { stage in stage.advance(to: .findingServer) }
    #expect(session.stage == .cloud(.findingServer))
}

@Test func streamSessionDatacenterChoiceIsAStartingWaitThatSurvivesSteps() {
    var session = StreamSession.idle
    session.begin(first, source: cloud)
    session.updateStage(for: first) { stage in stage.advance(to: .findingServer) }
    let moved13 = session.updateStage(for: first) { stage in stage.offer(offer) }
    #expect(moved13)
    let moved14 = session.updateStage(for: first) { stage in stage.offer(offer) }
    #expect(!moved14)
    let moved15 = session.updateStage(for: first) { stage in stage.queue(at: 3) }
    #expect(!moved15)
    let chosen = session.updateStage(for: first) { stage in
        stage.updateDatacenterChoice { choice in
            choice.choose("Osaka")
        }
    }
    #expect(chosen)
    session.updateStage(for: first) { stage in stage.advance(to: .connecting) }
    #expect(session.stage?.datacenterChoice == .sending(offer, name: "Osaka"))
    let sent = session.updateStage(for: first) { stage in
        stage.updateDatacenterChoice { choice in
            choice.sent("Osaka", accepted: true)
        }
    }
    #expect(sent)
    #expect(session.stage?.datacenterChoice == .sent(name: "Osaka"))
    let moved16 = session.updateStage(for: first) { stage in stage.datacenterSelected() }
    #expect(moved16)
    #expect(session.stage == .cloud(.connecting))
}

@Test func streamSessionIgnoresAnEmptyDatacenterOffer() {
    var session = StreamSession.idle
    session.begin(first, source: cloud)
    let moved17 = session.updateStage(for: first) { stage in
        stage.offer(CloudDatacenterLaunchOffer(entries: [], timeoutSeconds: 5))
    }
    #expect(!moved17)
}

@Test func streamSessionPausesForTheLoginPINAndResumesTheSameStage() {
    var session = StreamSession.idle
    session.begin(first, source: console)
    session.updateStage(for: first) { stage in stage.retried(1) }
    let moved18 = session.requestAccess(.controllerPasscode(pad: 1, retry: false), for: first)
    #expect(!moved18)
    let moved19 = session.requestAccess(.loginPIN(retry: false), for: first)
    #expect(moved19)
    #expect(session == .awaitingAccess(first, .loginPIN(retry: false), resuming: .connecting(attempt: 1)))
    let moved20 = session.requestAccess(.loginPIN(retry: true), for: first)
    #expect(moved20)
    let moved21 = session.accessGranted(for: first)
    #expect(moved21)
    #expect(session == .starting(first, .connecting(attempt: 1)))
}

@Test func streamSessionPlaysFromTheFirstFrameEvenWhileWaitingForAccess() {
    var session = StreamSession.idle
    session.begin(first, source: console)
    session.requestAccess(.loginPIN(retry: false), for: first)
    let moved22 = session.firstFrame(for: second)
    #expect(!moved22)
    let moved23 = session.firstFrame(for: first)
    #expect(moved23)
    #expect(session == .playing(first))
    #expect(session.isStreaming)
}

@Test func streamSessionReconnectsAndReturnsToPlaying() {
    var session = StreamSession.playing(first)
    let moved24 = session.reconnecting(1, for: first)
    #expect(moved24)
    let moved25 = session.reconnecting(2, for: first)
    #expect(moved25)
    #expect(session.reconnectAttempt == 2)
    let moved26 = session.reconnected(for: first)
    #expect(moved26)
    #expect(session == .playing(first))
    let moved27 = session.reconnected(for: first)
    #expect(!moved27)
}

@Test func streamSessionStopsALiveSessionAndEndsWithTheExitOutcome() {
    var session = StreamSession.playing(first)
    let moved28 = session.stop(.restMode)
    #expect(moved28 == first)
    #expect(session == .stopping(first, .restMode))
    let moved29 = session.stop(.disconnect)
    #expect(moved29 == nil)
    let moved30 = session.end(first)
    #expect(!moved30)
    let moved31 = session.fail(first, with: .renderer)
    #expect(!moved31)
    let moved32 = session.stopped(first, outcome: .restRefused)
    #expect(moved32)
    #expect(session == .ended(first, .left(.restRefused)))
}

@Test func streamSessionStopDismissesAnEndedOrFailedSession() {
    var session = StreamSession.failed(first, .renderer)
    let moved33 = session.stop(.disconnect)
    #expect(moved33 == nil)
    #expect(session == .idle)
}

@Test func streamSessionRefusesEventsFromAnotherSession() {
    var session = StreamSession.idle
    session.begin(first, source: console)
    let moved34 = session.end(second)
    #expect(!moved34)
    let moved35 = session.fail(second, with: .busy)
    #expect(!moved35)
    let moved36 = session.fail(first, with: .timedOut(.startAttempt(0)))
    #expect(moved36)
    #expect(session.failure == .timedOut(.startAttempt(0)))
    let moved37 = session.begin(second, source: console)
    #expect(moved37)
    let moved38 = session.firstFrame(for: first)
    #expect(!moved38)
}

@Test func streamSessionEndedByTheConsoleCanBeDismissed() {
    var session = StreamSession.playing(first)
    let moved39 = session.end(first)
    #expect(moved39)
    #expect(session == .ended(first, .finished))
    let moved40 = session.dismiss()
    #expect(moved40)
    #expect(session == .idle)
    let moved41 = session.dismiss()
    #expect(!moved41)
}

@Test func streamDeadlinesMatchTheStartStage() {
    #expect(StreamDeadline(.connecting(attempt: 2)).duration == .seconds(75))
    #expect(StreamDeadline(.cloud(.connecting)).duration == .seconds(30))
    #expect(StreamDeadline(.cloud(.preparing, wait: .queued(position: 3))).duration == .seconds(180))
}

@Test func streamSourceRetryDropsTheCloudClearance() {
    final class Cleared: Sendable {}
    let request = CloudStreamRequest(
        profile: ProfileID(),
        title: CloudStreamTitle(product: ProductID(rawValue: "EP0001")!, name: "Game", service: .psNow),
        clearance: CloudLaunchClearanceToken(Cleared())
    )
    guard case .cloud(let retried) = StreamSource.cloud(request).retried else {
        Issue.record("The retried source is not a cloud source")
        return
    }
    #expect(retried.clearance == nil)
    #expect(retried.title == request.title)
}
