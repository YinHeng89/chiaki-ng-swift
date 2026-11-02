import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Foundation
import Testing

private typealias Progress = OperationProgress

@Test func aPairingReportFromTheCoreNamesItsStep() {
    var progress = libchiaking.consoles.PairingProgress()
    progress.step = .sending_request
    #expect(OperationProgressReader.progress(of: progress)
        == OperationProgress(step: .pairing(.sendingRequest), elapsedMilliseconds: 0))
}

@Test func coreValuesCompareEqualOnlyWhenEveryFieldMatches() {
    let position = Progress.Position(number: 7, total: 10)
    #expect(position == Progress.Position(number: 7, total: 10))
    #expect(position != Progress.Position(number: 8, total: 10))
    #expect(position != Progress.Position(number: 7, total: 11))

    let wait = Progress.Wait(reason: .serverQueue, nextTry: .milliseconds(15000))
    #expect(wait == Progress.Wait(reason: .serverQueue, nextTry: .milliseconds(15000)))
    #expect(wait != Progress.Wait(reason: .dataMigration, nextTry: .milliseconds(15000)))
    #expect(wait != Progress.Wait(reason: .serverQueue, nextTry: .milliseconds(5000)))
    #expect(wait != Progress.Wait(reason: .serverQueue))

    let candidates = Progress.Candidates(local: 2, publicAddress: 1, portGuessed: 75)
    let route = Progress.Route(step: .routeChosen, purpose: .stream, candidates: candidates, chosen: .local)
    #expect(route == Progress.Route(
        step: .routeChosen,
        purpose: .stream,
        candidates: candidates,
        chosen: .local
    ))
    #expect(route != Progress.Route(
        step: .confirmingRoute,
        purpose: .stream,
        candidates: candidates,
        chosen: .local
    ))
    #expect(route != Progress.Route(
        step: .routeChosen,
        purpose: .control,
        candidates: candidates,
        chosen: .local
    ))
    #expect(route != Progress.Route(step: .routeChosen, purpose: .stream, chosen: .local))
    #expect(route != Progress.Route(step: .routeChosen, purpose: .stream, candidates: candidates))
    #expect(route != Progress.Route(
        step: .routeChosen, purpose: .stream, candidates: candidates, chosen: .discovered
    ))
    #expect(route != Progress.Route(
        step: .routeChosen, purpose: .stream,
        candidates: Progress.Candidates(local: 2, publicAddress: 1, portGuessed: 74), chosen: .local
    ))

    let failure = Progress.Failure(cause: .controlTimeout, consoleQuit: .consoleShutDown)
    #expect(failure == Progress.Failure(cause: .controlTimeout, consoleQuit: .consoleShutDown))
    #expect(failure != Progress.Failure(cause: .controlRefused, consoleQuit: .consoleShutDown))
    #expect(failure != Progress.Failure(cause: .controlTimeout, consoleQuit: .consoleInUse))
    #expect(failure != Progress.Failure(cause: .controlTimeout))
    #expect(failure != Progress.Failure(consoleQuit: .consoleShutDown))

    let waiting = Progress(
        step: .connect(.wakingConsole),
        wait: wait,
        route: route,
        previousFailure: failure
    )
    #expect(waiting == Progress(
        step: .connect(.wakingConsole),
        wait: wait,
        route: route,
        previousFailure: failure
    ))
    #expect(waiting != Progress(step: .connect(.wakingConsole), route: route, previousFailure: failure))
}

@Test func aConnectReportFromTheCoreKeepsEveryTypedValue() {
    var route = libchiaking.progress.InternetRoute()
    route.step = .route_chosen
    route.purpose = .stream
    route.candidates = .init(libchiaking.progress.InternetRoute.Candidates(
        local: 2,
        public_address: 1,
        port_guessed: 75
    ))
    route.chosen = .init(.port_guessed)
    var failure = libchiaking.play.AttemptFailure()
    failure.cause = .init(.control_timeout)
    failure.console_quit = .init(.console_shut_down)
    failure.offline = true
    var report = libchiaking.play.ConnectProgress()
    report.step = .waking_console
    report.elapsed = .init(.milliseconds(2500))
    report.attempt = 3
    report.reconnecting = true
    report.wait = .init(libchiaking.progress.Wait(
        reason: .console_waking,
        next_try_in: .init(.init(.milliseconds(2000)))
    ))
    report.previous_failure = .init(failure)
    report.route = .init(route)
    #expect(OperationProgressReader.progress(of: report) == Progress(
        step: .connect(.wakingConsole),
        attempt: 3,
        elapsedMilliseconds: 2500,
        wait: ProgressWait(reason: .consoleWaking, nextTry: .milliseconds(2000)),
        route: Progress.Route(
            step: .routeChosen,
            purpose: .stream,
            candidates: Progress.Candidates(local: 2, publicAddress: 1, portGuessed: 75),
            chosen: .portGuessed
        ),
        reconnecting: true,
        previousFailure: Progress.Failure(
            cause: .controlTimeout,
            consoleQuit: .consoleShutDown,
            offline: true
        )
    ))
    report.wait = .init()
    report.previous_failure = .init()
    report.route = .init()
    #expect(OperationProgressReader.progress(of: report) == Progress(
        step: .connect(.wakingConsole),
        attempt: 3,
        elapsedMilliseconds: 2500,
        reconnecting: true
    ))
}

@Test func aLaunchReportFromTheCoreKeepsEveryTypedValue() throws {
    var counts = libchiaking.play.LaunchProgress.Counts()
    counts.step = .init(libchiaking.progress.Position(number: 7, of: 10))
    counts.attempt = .init(2)
    counts.wait = .init(libchiaking.progress.Wait(
        reason: .previous_session_closing,
        next_try_in: .init(.init(.milliseconds(10000)))
    ))
    let reserving = try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .reserving_server, counts)
        .value)
    #expect(OperationProgressReader.progress(of: reserving.after(.init(.seconds(3)))) == Progress(
        step: .launch(.reservingServer),
        position: Progress.Position(number: 7, total: 10),
        attempt: 2,
        elapsedMilliseconds: 3000,
        wait: ProgressWait(reason: .previousSessionClosing, nextTry: .milliseconds(10000))
    ))
    counts = libchiaking.play.LaunchProgress.Counts()
    counts.step = .init(libchiaking.progress.Position(number: 8, of: 10))
    counts.measured = .init(libchiaking.progress.Position(number: 3, of: 9))
    let measuring = try #require(libchiaking.play.LaunchProgress
        .at(.ps5_cloud, .measuring_datacenters, counts).value)
    #expect(OperationProgressReader.progress(of: measuring) == Progress(
        step: .launch(.measuringDatacenters),
        position: Progress.Position(number: 8, total: 10),
        attempt: 0,
        measured: Progress.Position(number: 3, total: 9)
    ))
    counts = libchiaking.play.LaunchProgress.Counts()
    counts.queue_position = .init(4)
    let queued = try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .allocating_server, counts)
        .value)
    #expect(OperationProgressReader.progress(of: queued)
        == Progress(step: .launch(.allocatingServer), attempt: 0, queuePosition: 4))
    counts.wait = .init(libchiaking.progress.Wait(
        reason: .server_queue,
        next_try_in: .init(.init(.milliseconds(15000)))
    ))
    counts.wait_time_estimate_seconds = .init(245)
    let estimated = try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .allocating_server, counts)
        .value)
    #expect(OperationProgressReader.progress(of: estimated)?.waitTimeEstimateSeconds == 245)
    counts.wait = .init()
    #expect(libchiaking.play.LaunchProgress.at(.ps5_cloud, .allocating_server, counts).value == nil)
    counts = libchiaking.play.LaunchProgress.Counts()
    counts.migration_percent = .init(62)
    let migrating = try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .migrating_data, counts)
        .value)
    #expect(OperationProgressReader.progress(of: migrating)
        == Progress(step: .launch(.migratingData), attempt: 0, migrationPercent: 62))
    counts = libchiaking.play.LaunchProgress.Counts()
    counts.bandwidth_kbps = .init(55000)
    counts.bandwidth_age = .init(.init(.seconds(720)))
    let measured = try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .measuring_bandwidth, counts)
        .value)
    let bandwidth = try #require(OperationProgressReader.progress(of: measured))
    #expect(bandwidth.bandwidthKbps == 55000)
    #expect(bandwidth.bandwidthAgeSeconds == 720)
    #expect(OperationProgressReader.progress(of: libchiaking.play.LaunchProgress(.ps5_cloud)) == nil)
}
