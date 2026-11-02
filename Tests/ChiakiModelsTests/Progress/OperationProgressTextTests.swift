import Foundation
import Testing
@testable import ChiakiModels

private typealias Progress = OperationProgress
private typealias Text = OperationProgressText

private func distinct(_ labels: [String]) {
    #expect(labels.allSatisfy { !$0.isEmpty })
    #expect(Set(labels).count == labels.count)
}

@Test func everyWaitReasonIsShownWithItsOwnWords() {
    let shown: [Progress.WaitReason: String] = [
        .previousSessionClosing: "Waiting for your previous session to close",
        .serverQueue: "Waiting in the server queue",
        .dataMigration: "Waiting for your data to move",
        .datacenterChoice: "Waiting for a datacenter choice",
        .titleNotReady: "The title is not ready yet",
        .networkUnreachable: "The network is unreachable",
        .consoleWaking: "Waiting for the console to wake",
        .consoleJoining: "Waiting for the console to join",
        .consoleAnswering: "Waiting for the console to answer",
        .connectionRetry: "Waiting before the next attempt",
        .recentCloudSession: "Waiting since last cloud stream"
    ]
    #expect(shown.count == Progress.WaitReason.allCases.count)
    for reason in Progress.WaitReason.allCases {
        #expect(Text.label(reason) == shown[reason])
    }
}

@Test func everyLaunchActivityIsShownWithItsOwnWords() {
    let shown: [Progress.LaunchActivity: String] = [
        .clearingWithCatalog: "Checking the title with the catalog",
        .checkingDevice: "Checking this device",
        .openingTitleSession: "Opening the title session",
        .resolvingTitle: "Finding the title",
        .takingFreeLicence: "Taking the free licence",
        .openingAccountSession: "Opening the account session",
        .reservingServer: "Reserving a server",
        .measuringDatacenters: "Measuring datacenters",
        .waitingForDatacenterChoice: "Choosing a datacenter",
        .allocatingServer: "Allocating a server",
        .migratingData: "Moving your data",
        .connectingToServer: "Connecting to the server",
        .measuringBandwidth: "Measuring your connection",
        .loadingLibrary: "Loading your library",
        .checkingMembership: "Checking your membership",
        .checkingCloudStreaming: "Checking PlayStation Plus Premium",
        .checkingOwnership: "Checking ownership",
        .checkingEntitlement: "Checking your copy of the game",
        .resolvingCloudGame: "Finding the cloud game",
        .checkingExclusions: "Checking PlayStation's restrictions",
        .checkingRelease: "Checking the release date"
    ]
    #expect(shown.count == Progress.LaunchActivity.allCases.count)
    for activity in Progress.LaunchActivity.allCases {
        #expect(Text.label(activity) == shown[activity])
        #expect(Text(Progress(step: .launch(activity))).title == shown[activity])
    }
}

@Test func everyConnectStepIsShownWithItsOwnWords() {
    let shown: [Progress.ConnectStep: String] = [
        .findingConsole: "Finding the console",
        .openingAccountSession: "Opening the account session",
        .wakingConsole: "Waking the console",
        .pairing: "Pairing with the console",
        .reachingConsole: "Reaching the console",
        .openingStreamRoute: "Opening the stream route",
        .requestingSession: "Requesting the session",
        .openingControl: "Opening the control connection",
        .measuringConnection: "Measuring the connection",
        .startingStream: "Starting the stream"
    ]
    #expect(shown.count == Progress.ConnectStep.allCases.count)
    for step in Progress.ConnectStep.allCases {
        #expect(Text.label(step) == shown[step])
        #expect(Text(Progress(step: .connect(step))).title == shown[step])
    }
}

@Test func everyPairingStepIsShownWithItsOwnWords() {
    let shown: [Progress.PairingStep: String] = [
        .starting: "Starting",
        .openingAccountSession: "Opening the account session",
        .wakingConsole: "Asking the console to join",
        .reachingConsole: "Reaching the console",
        .sendingRequest: "Sending the pairing request",
        .waitingForAnswer: "Waiting for the console's answer",
        .saving: "Saving the pairing"
    ]
    #expect(shown.count == Progress.PairingStep.allCases.count)
    for step in Progress.PairingStep.allCases {
        #expect(Text.label(step) == shown[step])
        #expect(Text(Progress(step: .pairing(step))).title == shown[step])
    }
}

@Test func everyRouteStepIsShownForBothRoutes() {
    let control: [Progress.RouteStep: String] = [
        .openingAccountSession: "Opening the account session",
        .waitingForConsole: "Waiting for the console to join",
        .gatheringCandidates: "Gathering addresses for the control route",
        .exchangingOffers: "Exchanging offers for the control route",
        .testingCandidates: "Testing the control route",
        .routeChosen: "The control route is chosen",
        .confirmingRoute: "Confirming the control route",
        .switchingControl: "Switching control to the stream route"
    ]
    let stream: [Progress.RouteStep: String] = [
        .openingAccountSession: "Opening the account session",
        .waitingForConsole: "Waiting for the console to join",
        .gatheringCandidates: "Gathering addresses for the stream route",
        .exchangingOffers: "Exchanging offers for the stream route",
        .testingCandidates: "Testing the stream route",
        .routeChosen: "The stream route is chosen",
        .confirmingRoute: "Confirming the stream route",
        .switchingControl: "Switching control to the stream route"
    ]
    #expect(control.count == Progress.RouteStep.allCases.count)
    #expect(stream.count == Progress.RouteStep.allCases.count)
    #expect(Progress.RoutePurpose.allCases == [.control, .stream])
    for step in Progress.RouteStep.allCases {
        #expect(Text.label(Progress.Route(step: step, purpose: .control)) == control[step])
        #expect(Text.label(Progress.Route(step: step, purpose: .stream)) == stream[step])
        let routed = Progress(
            step: .connect(.reachingConsole), route: Progress.Route(step: step, purpose: .control)
        )
        #expect(Text(routed).title == control[step])
    }
}

@Test func everyRouteKindIsShownOnceChosen() {
    let shown: [Progress.RouteKind: String] = [
        .local: "Route over the local network",
        .publicAddress: "Route over the public address",
        .portGuessed: "Route over a guessed port",
        .discovered: "Route over an address the console answered from"
    ]
    #expect(shown.count == Progress.RouteKind.allCases.count)
    for kind in Progress.RouteKind.allCases {
        #expect(Text.label(kind) == shown[kind])
        let chosen = Progress(
            step: .connect(.openingStreamRoute),
            route: Progress.Route(step: .routeChosen, purpose: .stream, chosen: kind)
        )
        #expect(Text(chosen).lines == ["The stream route is chosen", shown[kind]])
    }
}

@Test func everyFailureCauseAndConsoleQuitHasItsOwnWords() {
    let causes = Progress.FailureCause.allCases.map { Text.label($0) }
    #expect(causes.allSatisfy { !$0.isEmpty })
    #expect(Set(causes).count == causes.count)
    distinct(Progress.ConsoleQuit.allCases.map { Text.label($0) })
    #expect(Text.label(.controlNetworkFailure) == "the control connection was lost")
    #expect(Text.label(.controlTimeout) == "the control connection timed out")
    #expect(Text.label(.routeFailed) == "no route to the console worked")
    #expect(Text.label(Progress.ConsoleQuit.consoleShutDown) == "the console shut down")
    #expect(Text.label(Progress.ConsoleQuit.consoleInUse) == "the console is in use")
    #expect(Text.label(Progress.ConsoleQuit.timeLimitReached) == "the streaming time limit was reached")
    for cause in Progress.FailureCause.allCases {
        let retry = Progress(
            step: .connect(.findingConsole), attempt: 2, previousFailure: Progress.Failure(cause: cause)
        )
        #expect(Text(retry).details == ["Attempt 2", "The last attempt failed: \(Text.label(cause))"])
    }
    for quit in Progress.ConsoleQuit.allCases {
        let retry = Progress(
            step: .connect(.findingConsole), attempt: 2,
            previousFailure: Progress.Failure(cause: .controlFailed, consoleQuit: quit)
        )
        #expect(Text(retry).details == ["Attempt 2", "The last attempt failed: \(Text.label(quit))"])
    }
}

@Test func aCloudLaunchWaitShowsItsStepReasonCountdownTriesAndElapsedTime() {
    let waiting = Progress(
        step: .launch(.reservingServer), position: Progress.Position(number: 7, total: 10), attempt: 2,
        elapsedMilliseconds: 23000,
        wait: Progress.Wait(reason: .previousSessionClosing, nextTry: .milliseconds(10000))
    )
    #expect(Text(waiting).lines == [
        "Reserving a server", "Step 7 of 10",
        "Waiting for your previous session to close, trying again in 10 s", "Tried 2 times", "23 s elapsed"
    ])
    #expect(Text(waiting, sinceReport: .seconds(4)).details == [
        "Step 7 of 10", "Waiting for your previous session to close, trying again in 6 s", "Tried 2 times",
        "27 s elapsed"
    ])
    #expect(Text(waiting, sinceReport: .seconds(30)).details[1]
        == "Waiting for your previous session to close, trying again now")
}

@Test func aCloudLaunchShowsMeasuredDatacentersQueueAndMigration() {
    let measuring = Progress(
        step: .launch(.measuringDatacenters), position: Progress.Position(number: 8, total: 10), attempt: 0,
        measured: Progress.Position(number: 3, total: 9)
    )
    #expect(Text(measuring).lines == ["Measuring datacenters", "Step 8 of 10", "Measured 3 of 9 datacenters"])
    let queued = Progress(
        step: .launch(.allocatingServer), attempt: 1,
        wait: Progress.Wait(reason: .serverQueue, nextTry: .milliseconds(15000)), queuePosition: 4,
        waitTimeEstimateSeconds: 245
    )
    #expect(Text(queued).lines == [
        "Allocating a server", "Position 4 in the queue", "Estimated wait: about 4 mins",
        "Waiting in the server queue, trying again in 15 s", "Tried once"
    ])
    #expect(Text(Progress(
        step: .launch(.allocatingServer), waitTimeEstimateSeconds: 45
    )).details == ["Estimated wait: under a minute"])
    #expect(Text(Progress(
        step: .launch(.allocatingServer), waitTimeEstimateSeconds: 90
    )).details == ["Estimated wait: about 1 min"])
    let migrating = Progress(
        step: .launch(.migratingData), attempt: 3, wait: Progress.Wait(reason: .dataMigration),
        migrationPercent: 62
    )
    #expect(Text(migrating).lines == [
        "Moving your data", "62% moved", "Waiting for your data to move", "Tried 3 times"
    ])
    let unreachable = Progress(
        step: .launch(.allocatingServer), attempt: 0,
        wait: Progress.Wait(reason: .networkUnreachable, nextTry: .milliseconds(5000))
    )
    #expect(Text(unreachable).details == ["The network is unreachable, trying again in 5 s"])
    let retried = Progress(
        step: .launch(.reservingServer), attempt: 2,
        wait: Progress.Wait(reason: .titleNotReady, nextTry: .milliseconds(0))
    )
    #expect(Text(retried).details == ["The title is not ready yet", "Tried 2 times"])
    let choosing = Progress(
        step: .launch(.waitingForDatacenterChoice), position: Progress.Position(number: 9, total: 10),
        attempt: 0,
        wait: Progress.Wait(reason: .datacenterChoice, nextTry: .milliseconds(15000))
    )
    #expect(Text(choosing, sinceReport: .seconds(5)).details == [
        "Step 9 of 10", "Waiting for a datacenter choice, trying again in 10 s"
    ])
}

@Test func anInternetRouteShowsItsCandidatesAndTheWaitForTheConsole() {
    let testing = Progress(
        step: .connect(.reachingConsole), elapsedMilliseconds: 4200,
        route: Progress.Route(
            step: .testingCandidates, purpose: .control,
            candidates: Progress.Candidates(local: 2, publicAddress: 1, portGuessed: 75)
        )
    )
    #expect(Text(testing).lines == [
        "Testing the control route", "78 addresses: 2 local, 1 public, 75 guessed", "4 s elapsed"
    ])
    let joining = Progress(
        step: .connect(.openingAccountSession), wait: Progress.Wait(reason: .consoleJoining),
        route: Progress.Route(step: .waitingForConsole, purpose: .control)
    )
    #expect(Text(joining).lines == ["Waiting for the console to join", "Waiting for the console to join"])
}

@Test func aRetryAndAReconnectShowTheWaitTheAttemptAndThePreviousFailure() {
    let waking = Progress(
        step: .connect(.wakingConsole), attempt: 2, elapsedMilliseconds: 9000,
        wait: Progress.Wait(reason: .consoleWaking, nextTry: .milliseconds(2000)),
        previousFailure: Progress.Failure(cause: .sessionRequestTimeout)
    )
    #expect(Text(waking).lines == [
        "Waking the console", "Waiting for the console to wake, trying again in 2 s", "Attempt 2",
        "The last attempt failed: the session request timed out", "9 s elapsed"
    ])
    let reconnecting = Progress(
        step: .connect(.findingConsole), attempt: 3,
        wait: Progress.Wait(reason: .connectionRetry, nextTry: .milliseconds(1500)), reconnecting: true,
        previousFailure: Progress.Failure(cause: .controlNetworkFailure)
    )
    #expect(Text(reconnecting, sinceReport: .seconds(1)).lines == [
        "Finding the console", "Waiting before the next attempt, trying again in 1 s", "Attempt 3",
        "The last attempt failed: the control connection was lost"
    ])
    #expect(Text(Progress(step: .connect(.findingConsole))).details.isEmpty)
}

@Test func pairingShowsItsStepAndTheWaitForTheConsolesAnswer() {
    let answering = Progress(
        step: .pairing(.waitingForAnswer), elapsedMilliseconds: 1200,
        wait: Progress.Wait(reason: .consoleAnswering)
    )
    #expect(Text(answering).lines == [
        "Waiting for the console's answer", "Waiting for the console to answer", "1 s elapsed"
    ])
    let routed = Progress(
        step: .pairing(.reachingConsole),
        route: Progress.Route(step: .confirmingRoute, purpose: .control, chosen: .local)
    )
    #expect(Text(routed).lines == ["Confirming the control route", "Route over the local network"])
}

@Test func measuringTheConnectionShowsTheBandwidthAndWhenItWasSaved() {
    var progress = Progress(step: .launch(.measuringBandwidth), attempt: 0)
    progress.bandwidthKbps = 55000
    #expect(Text(progress).details == ["55 Mbps"])
    progress.bandwidthAgeSeconds = 720
    #expect(Text(progress).details == ["55 Mbps saved 12 min ago"])
    #expect(progress.bandwidth?.statisticsDescription == "55 Mbps, measured 12 min before launch")
    #expect(CloudBandwidthReport(kbps: 32000).statisticsDescription == "32 Mbps, measured at launch")
    #expect(Progress(step: .launch(.allocatingServer)).bandwidth == nil)
}

@Test func theSettlingTimeAfterACloudStreamCountsDownInSeconds() {
    let settling = Progress(
        step: .launch(.reservingServer), attempt: 0,
        wait: Progress.Wait(reason: .recentCloudSession, nextTry: .milliseconds(20000))
    )
    #expect(Text(settling).details == ["Waiting 20 seconds since last cloud stream"])
    #expect(Text(settling, sinceReport: .seconds(19)).details == ["Waiting 1 second since last cloud stream"])
    #expect(Text(settling, sinceReport: .seconds(25))
        .details == ["Waiting 0 seconds since last cloud stream"])
}
