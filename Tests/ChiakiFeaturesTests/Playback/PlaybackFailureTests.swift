import ChiakiModels
import Testing
@testable import ChiakiFeatures

private let wakeNotReady = "The console did not become ready for Remote Play after the wake request."
private let connectionRefused = "The console refused the connection. Check Remote Play is available."
private let resourcesExhausted = "chiaki-ng ran out of network sockets or file handles. "
    + "Quit and reopen the app, then try again."

private struct FormerCode {
    let code: Int
    let outcome: StreamOutcome
    let message: String

    init(_ code: Int, _ outcome: StreamOutcome, _ message: String) {
        self.code = code
        self.outcome = outcome
        self.message = message
    }
}

private struct FormerRefusal {
    let code: Int
    let refusal: StreamOutcome.StartRefusal
    let message: String

    init(_ code: Int, _ refusal: StreamOutcome.StartRefusal, _ message: String) {
        self.code = code
        self.refusal = refusal
        self.message = message
    }
}

private let formerCodeMessages: [FormerCode] = [
    .init(1002, .consoleQuit(.sessionRequestUnknown), wakeNotReady),
    .init(4312, .startFailed(.controlNetworkFailure), wakeNotReady),
    .init(4313, .startFailed(.controlTimeout), wakeNotReady),
    .init(
        4612,
        .sessionFailed(.controlNetworkFailure),
        "The Ctrl connection failed. Check the network and try again."
    ),
    .init(4613, .sessionFailed(.controlTimeout), "The Ctrl connection timed out. Try again."),
    .init(4614, .sessionFailed(.controlTruncated), "The Ctrl response was incomplete. Try again."),
    .init(4615, .sessionFailed(.controlInvalidResponse), "The Ctrl response was invalid."),
    .init(4616, .sessionFailed(.controlTooLarge), "The Ctrl response was too large."),
    .init(4617, .sessionFailed(.controlRefused),
          "The console refused the Ctrl connection. Check Remote Play is available."),
    .init(
        4618,
        .sessionFailed(.controlHandoffFailure),
        "The Ctrl connection could not hand off to streaming."
    ),
    .init(
        4619,
        .sessionFailed(.sessionRequestTruncated),
        "The session setup response was incomplete. Try again."
    ),
    .init(4620, .sessionFailed(.sessionRequestNetworkFailure),
          "The session setup connection failed. Check the network and try again."),
    .init(4621, .sessionFailed(.sessionRequestTimeout), "Session setup timed out. Try again."),
    .init(4622, .sessionFailed(.sessionRequestInvalidResponse), "The session setup response was invalid."),
    .init(4623, .sessionFailed(.sessionRequestTooLarge), "The session setup response was too large."),
    .init(1003, .consoleQuit(.sessionRequestConnectionRefused), connectionRefused),
    .init(1009, .consoleQuit(.controlConnectionRefused), connectionRefused),
    .init(4317, .startFailed(.controlRefused), connectionRefused),
    .init(4327, .startFailed(.sessionRequestConnectionRefused), connectionRefused),
    .init(4328, .startFailed(.controlConnectionRefused), connectionRefused),
    .init(4627, .sessionFailed(.sessionRequestConnectionRefused), connectionRefused),
    .init(4628, .sessionFailed(.controlConnectionRefused), connectionRefused),
    .init(4329, .startFailed(.resourceExhausted), resourcesExhausted),
    .init(4629, .sessionFailed(.resourceExhausted), resourcesExhausted),
    .init(4729, .shutdownFailed(.resourceExhausted), resourcesExhausted),
    .init(1004, .consoleQuit(.consoleInUse), "Remote Play is already in use on this console."),
    .init(4624, .sessionFailed(.sessionRequestRefused),
          "The console refused session setup. Check Remote Play is available."),
    .init(4625, .sessionFailed(.sessionRequestVersionMismatch),
          "The console and client Remote Play versions do not match."),
    .init(4626, .sessionFailed(.sessionRequestInUse),
          "Remote Play is already in use on this console. Close the active session and try again."),
    .init(
        1006,
        .consoleQuit(.remotePlayVersionMismatch),
        "The console and client Remote Play versions don’t match."
    ),
    .init(
        1012,
        .consoleQuit(.consoleShutDown),
        "The video session stopped (console_quit.console_shut_down)."
    ),
    .init(4507, .sessionFailed(nil), "The video session stopped (session_failed)."),
    .init(4307, .startFailed(.pipelineFailed), "The video session stopped (start_failed.pipeline_failed)."),
    .init(4805, .mediaFailed(.decoderOutput), "The video session stopped (media_failed.decoder_output)."),
    .init(2, .left, "The video session stopped (left).")
]

@Test func anEndedTrialSaysSoOnACloudStreamWithoutOfferingARetry() {
    let ended = StreamFailure.stream(.consoleQuit(.trialEnded), overInternet: true)
    #expect(StreamFailureMessage(ended, kind: .cloud).text
        == "Your game trial has ended. Buy the game from the PlayStation Store to keep playing.")
    let timedOut = StreamFailure.stream(.consoleQuit(.timeLimitReached), overInternet: true)
    #expect(StreamFailureMessage(timedOut, kind: .cloud).text
        == "Streaming game closed because the time limit was reached.")
    let dropped = StreamFailure.stream(.consoleQuit(.consoleDisconnected), overInternet: true)
    #expect(StreamFailureMessage(dropped, kind: .cloud).text
        == "The cloud session could not continue (console_quit.console_disconnected). Try again.")
}

@Test func aReachedTimeLimitSaysTheStreamingGameClosed() {
    for overInternet in [false, true] {
        let failure = PlaybackFailure.stream(.consoleQuit(.timeLimitReached), overInternet: overInternet)
        let message = PlaybackFailureMessage.text(for: failure)
        #expect(message == "Streaming game closed because the time limit was reached.")
    }
}

@Test func everyFormerCodeMessageSurvivesAsATypedOutcome() {
    for entry in formerCodeMessages {
        #expect(
            PlaybackFailureMessage.text(for: .stream(entry.outcome, overInternet: false)) == entry.message,
            "former code \(entry.code)"
        )
    }
}

private let formerRefusalMessages: [FormerRefusal] = [
    .init(4900, .busy, "The previous stream is still closing. Try again in a moment."),
    .init(4901, .notPaired, PlaybackFailureMessage.text(for: .credentials)),
    .init(4908, .unknownUser, PlaybackFailureMessage.text(for: .credentials)),
    .init(4909, .unknownConsole, PlaybackFailureMessage.text(for: .credentials)),
    .init(4903, .remotePlayDisabled, PlaybackFailureMessage.text(for: .remoteDisabled)),
    .init(4904, .signInExpired, "Sign in to PlayStation again to play over the internet."),
    .init(4905, .needsPSNSignIn, "Sign in to PlayStation again to play over the internet."),
    .init(4906, .invalidPreferences, "The stream settings were rejected. Check the picture settings."),
    .init(4201, .noDecoder, PlaybackFailureMessage.text(for: .renderer)),
    .init(4911, .coreClosed, "Streaming is unavailable. Quit and reopen the app."),
    .init(4913, .cancelled, "Start cancelled"),
    .init(4907, .launchRefused, "The video session stopped (start_refused.launch_refused).")
]

@Test func everyFormerStartRefusalMessageSurvives() {
    for entry in formerRefusalMessages {
        #expect(
            PlaybackFailureMessage.text(for: .stream(.startRefused(entry.refusal), overInternet: false))
                == entry.message,
            "former code \(entry.code)"
        )
    }
    #expect(PlaybackFailureMessage.text(for: .stream(.startRefused(.consoleUnreachable), overInternet: false))
        == PlaybackFailureMessage.text(for: .consoleNotOnLocalNetwork))
    #expect(PlaybackFailureMessage.text(for: .stream(.startRefused(.consoleUnreachable), overInternet: true))
        == PlaybackFailureMessage.text(for: .remoteUnavailable))
    #expect(PlaybackFailureMessage
        .text(for: .busy) == "The previous stream is still closing. Try again in a moment.")
}

@Test func aNetworkFailureIsNotReportedAsAConsoleLeavingTheAccount() {
    let internet = PlaybackFailureMessage.text(for: .stream(
        .startRefused(.networkUnreachable),
        overInternet: true
    ))
    #expect(internet.hasPrefix("PlayStation Network couldn’t be reached."))
    #expect(internet != PlaybackFailureMessage.text(for: .remoteUnavailable))
    let home = PlaybackFailureMessage.text(for: .stream(
        .startRefused(.networkUnreachable),
        overInternet: false
    ))
    #expect(home.contains("Local Network access"))
}

@Test func onlyStreamFailuresCarryAnOutcome() {
    #expect(PlaybackFailure.stream(.consoleQuit(.consoleInUse), overInternet: true).outcome
        == .consoleQuit(.consoleInUse))
    #expect(PlaybackFailure.credentials.outcome == nil)
    #expect(PlaybackFailure.wakeRefused.outcome == nil)
}

@Test func aRejectedPairingAsksForUnpairing() {
    let failure = PlaybackFailure.stream(.startFailed(.pairingRejected), overInternet: true)
    #expect(failure.rejectsPairing)
    #expect(
        PlaybackFailureMessage.text(for: failure)
            == "The console no longer accepts this pairing. Unpair, then pair again."
    )
    #expect(!PlaybackFailure.stream(.startFailed(.controlRefused), overInternet: false).rejectsPairing)
    #expect(!PlaybackFailure.credentials.rejectsPairing)
}

@Test func aCloudStreamThatFellSilentSaysTheConnectionWasLost() {
    let lost = StreamFailure.stream(.sessionFailed(.connectionLost), overInternet: true)
    #expect(StreamFailureMessage(lost, kind: .cloud).text == CloudPlaybackFailureMessage.connectionLost)
    #expect(CloudPlaybackFailureMessage.text(for: .stream(.sessionFailed(.connectionLost)))
        == CloudPlaybackFailureMessage.connectionLost)
    let broken = StreamFailure.stream(.sessionFailed(.pipelineFailed), overInternet: true)
    #expect(StreamFailureMessage(broken, kind: .cloud).text
        == "The cloud session could not continue (session_failed.pipeline_failed). Try again.")
}

@Test func anUnpairedPS4OverTheInternetAsksForPairingAtHome() {
    let failure = PlaybackFailure.stream(.startFailed(.unpairedConsole), overInternet: true)
    #expect(!failure.rejectsPairing)
    #expect(
        PlaybackFailureMessage.text(for: failure)
            == "PlayStation Network connected to a PS4 that isn’t paired with chiaki-ng. "
            + "Pair that PS4 at home first, or make this PS4 the primary console on your account."
    )
}

@Test func aLostConnectionAsksToCheckTheNetwork() {
    for outcome in [StreamOutcome.sessionFailed(.connectionLost), .startFailed(.connectionLost)] {
        #expect(
            PlaybackFailureMessage.text(for: .stream(outcome, overInternet: false))
                == "The connection to the console was lost. Check the network and try again."
        )
    }
}

@Test func aHostRefusalAsksThePlayerToFreeTheDevice() {
    #expect(
        PlaybackFailureMessage.text(for: .stream(.startRefused(.hostRefused), overInternet: false))
            == "The stream couldn’t start on this device. Close other apps and try again."
    )
}
