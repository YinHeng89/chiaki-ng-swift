import ChiakiBridge
import ChiakiModels

/// Reads the progress the core reports for a stream start, a cloud launch or a pairing into
/// `OperationProgress`.
///
/// Every core enum is switched over exhaustively, so a case the core adds fails to compile here instead of
/// being mapped silently.
public enum OperationProgressReader {
    /// The progress of a console stream start.
    ///
    /// - Parameter progress: What the core reported.
    /// - Returns: The model progress.
    public static func progress(of progress: libchiaking.play.ConnectProgress) -> OperationProgress {
        operation(
            step: .connect(step(of: progress.step)),
            status: progress.status(),
            route: progress.route.value.map(route(of:)),
            reconnecting: progress.reconnecting,
            previousFailure: progress.previous_failure.value.map(failure(of:))
        )
    }

    /// The progress of a pairing.
    ///
    /// - Parameter progress: What the core reported.
    /// - Returns: The model progress.
    public static func progress(of progress: libchiaking.consoles.PairingProgress) -> OperationProgress {
        operation(
            step: .pairing(step(of: progress.step)),
            status: progress.status(),
            route: progress.route.value.map(route(of:))
        )
    }

    /// The progress of a cloud launch.
    ///
    /// - Parameter progress: What the core reported.
    /// - Returns: The model progress, or `nil` when the launch reported no activity yet.
    public static func progress(of progress: libchiaking.play.LaunchProgress) -> OperationProgress? {
        guard let activity = progress.activity().value else {
            return nil
        }
        var operation = operation(step: .launch(Self.activity(of: activity)), status: progress.status())
        operation.attempt = progress.attempt().value.map { Int($0) } ?? 0
        operation.measured = progress.measured().value.map(position(of:))
        operation.queuePosition = progress.queue_position().value.map { Int($0) }
        operation.waitTimeEstimateSeconds = progress.wait_time_estimate_seconds().value.map { Int($0) }
        operation.migrationPercent = progress.migration_percent().value.map { Int($0) }
        operation.bandwidthKbps = progress.bandwidth_kbps().value.map { Int($0) }
        operation.bandwidthAgeSeconds = progress.bandwidth_age().value.map { Int($0.count()) }
        return operation
    }

    /// The cloud start step a launch report stands for.
    ///
    /// - Parameters:
    ///   - progress: What the core reported.
    ///   - playing: Whether the stream is already playing, which has no step.
    /// - Returns: The step, or `nil` once the stream plays.
    public static func step(of progress: libchiaking.play.LaunchProgress, playing: Bool) -> CloudStartStep? {
        guard !playing else {
            return nil
        }
        switch progress.phase() {
        case .starting:
            return .checking
        case .preparing:
            return .preparing
        case .finding_server:
            return .findingServer
        case .connecting:
            return .connecting
        }
    }

    private static func operation(
        step: OperationProgress.Step,
        status: libchiaking.progress.Status,
        route: OperationProgress.Route? = nil,
        reconnecting: Bool = false,
        previousFailure: OperationProgress.Failure? = nil
    ) -> OperationProgress {
        OperationProgress(
            step: step,
            position: status.position.value.map(position(of:)),
            attempt: Int(status.attempt),
            elapsedMilliseconds: status.elapsed.value.map { Int($0.count() / 1000) },
            wait: status.wait.value.map(wait(of:)),
            route: route,
            reconnecting: reconnecting,
            previousFailure: previousFailure
        )
    }

    private static func position(of position: libchiaking.progress.Position) -> ProgressPosition {
        ProgressPosition(number: Int(position.number), total: Int(position.of))
    }

    private static func wait(of wait: libchiaking.progress.Wait) -> ProgressWait {
        ProgressWait(
            reason: reason(of: wait.reason),
            nextTry: wait.next_try_in.value.map { .milliseconds($0.count()) }
        )
    }

    private static func route(of route: libchiaking.progress.InternetRoute) -> InternetRoute {
        InternetRoute(
            step: step(of: route.step),
            purpose: purpose(of: route.purpose),
            candidates: route.candidates.value.map { candidates in
                InternetRoute.Candidates(
                    local: Int(candidates.local),
                    publicAddress: Int(candidates.public_address),
                    portGuessed: Int(candidates.port_guessed)
                )
            },
            chosen: route.chosen.value.map(kind(of:))
        )
    }

    private static func failure(of failure: libchiaking.play.AttemptFailure) -> AttemptFailure {
        AttemptFailure(
            cause: failure.cause.value.map(StreamOutcomeReader.cause(of:)),
            consoleQuit: failure.console_quit.value.map(StreamOutcomeReader.quitReason(of:)),
            offline: failure.offline
        )
    }

    private static func activity(of value: libchiaking.play.LaunchActivity) -> LaunchActivity {
        switch value {
        case .clearing_with_catalog:
            .clearingWithCatalog
        case .checking_device:
            .checkingDevice
        case .opening_title_session:
            .openingTitleSession
        case .resolving_title:
            .resolvingTitle
        case .taking_free_licence:
            .takingFreeLicence
        case .opening_account_session:
            .openingAccountSession
        case .reserving_server:
            .reservingServer
        case .measuring_datacenters:
            .measuringDatacenters
        case .waiting_for_datacenter_choice:
            .waitingForDatacenterChoice
        case .allocating_server:
            .allocatingServer
        case .migrating_data:
            .migratingData
        case .connecting_to_server:
            .connectingToServer
        case .measuring_bandwidth:
            .measuringBandwidth
        case .loading_library:
            .loadingLibrary
        case .checking_membership:
            .checkingMembership
        case .checking_cloud_streaming:
            .checkingCloudStreaming
        case .checking_ownership:
            .checkingOwnership
        case .checking_entitlement:
            .checkingEntitlement
        case .resolving_cloud_game:
            .resolvingCloudGame
        case .checking_exclusions:
            .checkingExclusions
        case .checking_release:
            .checkingRelease
        }
    }

    private static func step(of value: libchiaking.play.ConnectStep) -> ConnectStep {
        switch value {
        case .finding_console:
            .findingConsole
        case .opening_account_session:
            .openingAccountSession
        case .waking_console:
            .wakingConsole
        case .pairing:
            .pairing
        case .reaching_console:
            .reachingConsole
        case .opening_stream_route:
            .openingStreamRoute
        case .requesting_session:
            .requestingSession
        case .opening_control:
            .openingControl
        case .measuring_connection:
            .measuringConnection
        case .starting_stream:
            .startingStream
        }
    }

    private static func step(of value: libchiaking.consoles.PairingStep) -> PairingStep {
        switch value {
        case .starting:
            .starting
        case .opening_account_session:
            .openingAccountSession
        case .waking_console:
            .wakingConsole
        case .reaching_console:
            .reachingConsole
        case .sending_request:
            .sendingRequest
        case .waiting_for_answer:
            .waitingForAnswer
        case .saving:
            .saving
        }
    }

    private static func reason(of value: libchiaking.progress.WaitReason) -> ProgressWaitReason {
        switch value {
        case .previous_session_closing:
            .previousSessionClosing
        case .server_queue:
            .serverQueue
        case .data_migration:
            .dataMigration
        case .datacenter_choice:
            .datacenterChoice
        case .title_not_ready:
            .titleNotReady
        case .network_unreachable:
            .networkUnreachable
        case .console_waking:
            .consoleWaking
        case .console_joining:
            .consoleJoining
        case .console_answering:
            .consoleAnswering
        case .connection_retry:
            .connectionRetry
        case .recent_cloud_session:
            .recentCloudSession
        }
    }

    private static func step(of value: libchiaking.progress.InternetRoute.Step) -> InternetRoute.Step {
        switch value {
        case .opening_account_session:
            .openingAccountSession
        case .waiting_for_console:
            .waitingForConsole
        case .gathering_candidates:
            .gatheringCandidates
        case .exchanging_offers:
            .exchangingOffers
        case .testing_candidates:
            .testingCandidates
        case .route_chosen:
            .routeChosen
        case .confirming_route:
            .confirmingRoute
        case .switching_control:
            .switchingControl
        }
    }

    private static func purpose(of value: libchiaking.progress.InternetRoute.Purpose) -> InternetRoute
        .Purpose {
        switch value {
        case .control:
            .control
        case .stream:
            .stream
        }
    }

    private static func kind(of value: libchiaking.progress.InternetRoute.Kind) -> InternetRoute.Kind {
        switch value {
        case .local:
            .local
        case .public_address:
            .publicAddress
        case .port_guessed:
            .portGuessed
        case .discovered:
            .discovered
        }
    }
}
