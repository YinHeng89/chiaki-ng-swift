import ChiakiModels
import ComposableArchitecture
import Foundation

/// Starts stream sessions, sends commands to the one that is live and reaches its player: the stream menu's
/// picture and sound tuning, the brightness marker and light measurement, the diagnostics overlay's samples
/// and appearance, the cloud stream's accessibility settings, invitations and saved data screen, the couch's
/// seat commands, controllers and lights, and the microphone captured into the stream. It also lists and joins
/// game invitations, invites friends and watches pushed alerts through PlayStation Network, and saves PS5
/// cloud captures to this device.
///
/// ``start`` returns the session's events in the order the player reported them. The stream finishes normally
/// when the console or service ended the session, throws a `ChiakiModels/StreamFailure` when it failed, and
/// stops the session when the caller stops listening. Every command names the session it is for and does
/// nothing for any other, so a command from a stopped session cannot reach the next one. The player
/// operations reach whichever player is live; the test value's do nothing, so reducer tests never reach a
/// player.
public struct StreamSessionClient: Sendable {
    /// Starts a session.
    ///
    /// - Parameters: the new session's id, which becomes its lease, and what to stream.
    /// - Returns: The session's events; `ChiakiModels/StreamFailure/busy` while another session holds the
    ///   lease.
    public var start: @Sendable (
        _ id: StreamSessionID,
        _ source: StreamSource
    ) -> AsyncThrowingStream<StreamSessionEvent, any Error>

    /// Sends a code the console asked for to a session, for the prompt it answers; returns whether the
    /// console accepted or was sent it.
    public var submitAccessCode: @Sendable (
        _ id: StreamSessionID,
        _ prompt: StreamAccessPrompt,
        _ code: StreamAccessCode
    ) async -> Bool

    /// Sends a change to a session console's on-screen keyboard; returns whether it was sent.
    public var keyboard: @Sendable (_ id: StreamSessionID, _ command: ConsoleKeyboardCommand) async -> Bool

    /// Asks a session's console to show its home screen; returns whether the request was sent.
    public var goHome: @Sendable (_ id: StreamSessionID) async -> Bool

    /// Chooses an offered cloud datacenter by name for a session; returns whether the core took it.
    public var selectDatacenter: @Sendable (_ id: StreamSessionID, _ name: String) async -> Bool

    /// Applies picture and sound settings the stream menu changed to a session.
    public var tune: @Sendable (_ id: StreamSessionID, _ tuning: StreamTuningConfiguration) async -> Void

    /// Leaves a session the way the user chose and waits until its player has closed; returns what happened
    /// to the console.
    public var leave: @Sendable (_ id: StreamSessionID, _ exit: StreamExitAction) async -> StreamExitOutcome

    /// Reads the saved picture and sound settings for a stream context into a tuning configuration.
    public var loadTuning: @Sendable (StreamTuningContext) async throws -> StreamTuningConfiguration

    /// Writes a tuning configuration back to the sound settings and the context's picture settings.
    public var saveTuning: @Sendable (StreamTuningContext, StreamTuningConfiguration) async throws -> Void

    /// Returns a stream of statistics samples taken from the current player at the packet-loss sampling
    /// interval.
    public var statisticsSamples: @Sendable () -> AsyncStream<StreamStatisticsSample>

    /// Switches the current player's HDR heatmap or highlight-clipping video analysis on the main actor.
    public var applyVideoAnalysis: @Sendable @MainActor (StreamVideoAnalysisMode) -> Void

    /// Loads the saved diagnostics overlay appearance from settings storage.
    ///
    /// - Throws: An error when the settings storage cannot be read or decoded.
    public var loadDiagnosticsAppearance: @Sendable () async throws -> StreamDiagnosticsAppearance

    /// Saves the diagnostics overlay appearance to settings storage.
    ///
    /// - Throws: An error when the settings storage cannot be written.
    public var saveDiagnosticsAppearance: @Sendable (StreamDiagnosticsAppearance) async throws -> Void

    /// Switches the renderer's light measurement on or off.
    public var measureLight: @Sendable @MainActor (_ measures: Bool) -> Void

    /// Shows or hides the brightness marker.
    public var showMarker: @Sendable @MainActor (_ shown: Bool) -> Void

    /// Places the brightness marker.
    public var placeMarker: @Sendable @MainActor (_ point: BrightnessMarker) -> Void

    /// Moves the brightness marker one step, unless the stick is gliding it.
    public var nudgeMarker: @Sendable @MainActor (_ nudge: BrightnessMarker.Nudge) -> Void

    /// Glides the brightness marker by the menu controller's left stick for the given seconds.
    public var glideMarker: @Sendable @MainActor (_ seconds: Double) -> Void

    /// Tells PS5 cloud whether the stream menu covers the stream.
    public var coverStreamWithMenu: @Sendable @MainActor (_ covers: Bool) -> Void

    /// Hands changed PlayStation accessibility settings to the stream: a cloud stream that has not launched
    /// yet starts with them, a playing PS5 cloud stream sends them on, and other streams ignore them.
    public var updateAccessibility: @Sendable @MainActor (_ settings: PlayStationAccessibilitySettings)
        -> Void

    /// Has a playing PS5 cloud or PS Now stream join a game invitation; returns `false` when no cloud stream
    /// is playing.
    public var joinInvitation: @Sendable @MainActor (_ invitationID: String, _ sessionID: String) -> Bool

    /// Has a playing PS Now stream open the cloud PS4's Application Saved Data Management screen; returns
    /// `false` when no PS Now stream is playing.
    public var openSavedData: @Sendable @MainActor () -> Bool

    /// Sends a couch seat command to the stream and returns whether the stream accepted it.
    public var runCouchCommand: @Sendable (CouchCommand) async -> Bool

    /// Hands menu navigation to the controller with this identifier, or back to player 1's for `nil`.
    public var handNavigation: @Sendable (UInt32?) async -> Void

    /// Applies a saved controls configuration to the stream's input.
    public var reloadControls: @Sendable (ControlsConfiguration) async -> Void

    /// Reads the connected controllers and which one player 1 uses.
    public var couchInventory: @Sendable () async -> CouchInventory

    /// Reads the current controller light colours.
    public var couchLights: @Sendable () -> CouchLights

    /// Reads whether the microphone should turn on automatically when a stream starts.
    public var microphoneStartPreference: @Sendable () async -> Bool

    /// Asks the system for microphone access and reports whether it was granted.
    public var requestMicrophonePermission: @Sendable () async -> Bool

    /// Starts capturing the microphone into the stream for the given operation and reports its progress until
    /// capture ends.
    public var captureMicrophone: @Sendable (UUID) -> AsyncStream<MicrophoneCaptureEvent>

    /// Mutes or unmutes the microphone capture for the given operation, returning a failure if it could not be
    /// applied.
    public var setMicrophoneMuted: @Sendable (UUID, Bool) async -> MicrophoneFailure?

    /// Turns the microphone mute indicator light on or off.
    public var indicateMicrophone: @Sendable (Bool) async -> Void

    /// Saves a PS5 cloud capture the console just uploaded, unless it follows a PlayStation setting that keeps
    /// it.
    public var saveCapture: @Sendable (_ capture: PendingCloudCapture, _ followsPlayStation: Bool) async
        -> Void

    /// Saves every cloud capture left from an earlier launch.
    public var resumeCaptures: @Sendable () async -> Void

    /// The profile's game invitations, newest first.
    public var invitations: @Sendable (_ profile: ProfileID) async throws(CloudInvitationFailure)
        -> [CloudGameInvitation]

    /// Sends a session's game intent to the profile's cloud console and waits for the command result.
    public var joinOnCloud: @Sendable (_ profile: ProfileID, _ sessionID: String) async
        throws(CloudInvitationFailure) -> Void

    /// Has one of the profile's home PS5s join a party and waits for the command result; PSN forbids the
    /// command on a cloud console.
    public var joinParty: @Sendable (
        _ profile: ProfileID,
        _ sessionID: String,
        _ console: HardwareID
    ) async throws(CloudInvitationFailure) -> Void

    /// Has one of the profile's home PS5s join a game session and waits for the command result.
    public var joinOn: @Sendable (
        _ profile: ProfileID,
        _ sessionID: String,
        _ console: HardwareID
    ) async throws(CloudInvitationFailure) -> Void

    /// Deletes notifications from the profile's list.
    public var dismissNotifications: @Sendable (_ profile: ProfileID, _ notificationIDs: [String]) async
        throws(CloudInvitationFailure) -> Void

    /// The game invitations and messages PSN pushes for the profile while the stream is read; it finishes
    /// when the profile cannot be watched.
    public var psnAlerts: @Sendable (_ profile: ProfileID) -> AsyncStream<PSNAlert>

    /// The profile's PSN friends, online friends first.
    public var friends: @Sendable (_ profile: ProfileID) async throws(CloudInvitationFailure) -> [PSNFriend]

    /// The game session the profile plays in for a title on a platform, or `nil` when it plays in none.
    public var ownGameSession: @Sendable (
        _ profile: ProfileID,
        _ titleID: String,
        _ platform: String
    ) async throws(CloudInvitationFailure) -> OwnGameSession?

    /// A link friends can open to join a game session.
    public var shareLink: @Sendable (_ profile: ProfileID, _ sessionID: String) async
        throws(CloudInvitationFailure) -> SessionLink

    /// Invites friends to a game session or a party.
    public var inviteFriends: @Sendable (
        _ profile: ProfileID,
        _ target: InvitationTarget,
        _ friendIDs: [String]
    ) async throws(CloudInvitationFailure) -> Void

    /// Creates a client from its operations; each defaults to the test behaviour.
    ///
    /// - Parameters:
    ///   - start: Starts a session; by default it reports an issue and fails with a renderer failure.
    ///   - submitAccessCode: Sends a code; by default it reports an issue and sends nothing.
    ///   - keyboard: Sends a keyboard change; by default it reports an issue and sends nothing.
    ///   - goHome: Asks for the home screen; by default it reports an issue and sends nothing.
    ///   - selectDatacenter: Chooses a datacenter; by default it reports an issue and chooses nothing.
    ///   - tune: Applies tuning to a session; by default it reports an issue.
    ///   - leave: Leaves a session; by default it reports an issue and reports the session left.
    ///   - loadTuning: Reads the tuning for a context; by default a default configuration.
    ///   - saveTuning: Writes the tuning; by default nothing.
    ///   - statisticsSamples: Samples the player's statistics; by default a stream that finishes at once.
    ///   - applyVideoAnalysis: Switches the video analysis; by default nothing.
    ///   - loadDiagnosticsAppearance: Loads the overlay appearance; by default the default appearance.
    ///   - saveDiagnosticsAppearance: Saves the overlay appearance; by default nothing.
    ///   - measureLight: Switches light measurement; by default nothing.
    ///   - showMarker: Shows or hides the brightness marker; by default nothing.
    ///   - placeMarker: Places the brightness marker; by default nothing.
    ///   - nudgeMarker: Moves the brightness marker one step; by default nothing.
    ///   - glideMarker: Glides the brightness marker; by default nothing.
    ///   - coverStreamWithMenu: Tells PS5 cloud whether the menu covers the stream; by default nothing.
    ///   - updateAccessibility: Hands changed accessibility settings to the stream; by default nothing.
    ///   - joinInvitation: Has a playing cloud stream join a game invitation; by default no stream joins.
    ///   - openSavedData: Has a playing PS Now stream open its saved data screen; by default none does.
    ///   - runCouchCommand: Sends a seat command; by default the stream accepts every command.
    ///   - handNavigation: Hands menu navigation to a controller; by default nothing.
    ///   - reloadControls: Applies a controls configuration; by default nothing.
    ///   - couchInventory: Reads the connected controllers; by default none.
    ///   - couchLights: Reads the controller light colours; by default none.
    ///   - microphoneStartPreference: Reads whether the microphone starts on; by default it does not.
    ///   - requestMicrophonePermission: Requests microphone access; by default it is refused.
    ///   - captureMicrophone: Starts capture for an operation; by default it fails as the stream is
    ///     unavailable.
    ///   - setMicrophoneMuted: Applies a mute state; by default it fails as the stream is unavailable.
    ///   - indicateMicrophone: Sets the mute indicator light; by default nothing.
    ///   - saveCapture: Saves a cloud capture; by default nothing.
    ///   - resumeCaptures: Saves the captures left from an earlier launch; by default nothing.
    ///   - invitations: Lists the profile's game invitations; by default none.
    ///   - joinOnCloud: Joins a player session through the profile's cloud console; by default it fails as
    ///     unavailable.
    ///   - joinParty: Joins a party on one of the profile's home PS5s; by default it fails as unavailable.
    ///   - joinOn: Joins a game session on one of the profile's home PS5s; by default it fails as unavailable.
    ///   - dismissNotifications: Deletes notifications from the profile's list; by default nothing.
    ///   - psnAlerts: Watches the profile's pushed invitations and messages; by default a stream that finishes
    ///     at once.
    ///   - friends: Lists the profile's friends; by default it fails as unavailable.
    ///   - ownGameSession: Finds the profile's game session for a title; by default it fails as unavailable.
    ///   - shareLink: Asks for a link to a game session; by default it fails as unavailable.
    ///   - inviteFriends: Invites friends to a session or party; by default it fails as unavailable.
    public init(
        start: @escaping @Sendable (
            StreamSessionID,
            StreamSource
        ) -> AsyncThrowingStream<StreamSessionEvent, any Error> = { _, _ in
            reportIssue("StreamSessionClient.start is unimplemented")
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: StreamFailure.renderer)
            }
        },
        submitAccessCode: @escaping @Sendable (
            StreamSessionID,
            StreamAccessPrompt,
            StreamAccessCode
        ) async -> Bool = { _, _, _ in
            reportIssue("StreamSessionClient.submitAccessCode is unimplemented")
            return false
        },
        keyboard: @escaping @Sendable (StreamSessionID, ConsoleKeyboardCommand) async -> Bool = { _, _ in
            reportIssue("StreamSessionClient.keyboard is unimplemented")
            return false
        },
        goHome: @escaping @Sendable (StreamSessionID) async -> Bool = { _ in
            reportIssue("StreamSessionClient.goHome is unimplemented")
            return false
        },
        selectDatacenter: @escaping @Sendable (StreamSessionID, String) async -> Bool = { _, _ in
            reportIssue("StreamSessionClient.selectDatacenter is unimplemented")
            return false
        },
        tune: @escaping @Sendable (StreamSessionID, StreamTuningConfiguration) async -> Void = { _, _ in
            reportIssue("StreamSessionClient.tune is unimplemented")
        },
        leave: @escaping @Sendable (StreamSessionID, StreamExitAction) async -> StreamExitOutcome = { _, _ in
            reportIssue("StreamSessionClient.leave is unimplemented")
            return .left
        },
        loadTuning: @escaping @Sendable (StreamTuningContext) async throws -> StreamTuningConfiguration = {
            _ in
            StreamTuningConfiguration()
        },
        saveTuning: @escaping @Sendable (StreamTuningContext, StreamTuningConfiguration) async throws
            -> Void = { _, _ in
            },
        statisticsSamples: @escaping @Sendable () -> AsyncStream<StreamStatisticsSample> = {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        applyVideoAnalysis: @escaping @Sendable @MainActor (StreamVideoAnalysisMode) -> Void = { _ in
        },
        loadDiagnosticsAppearance: @escaping @Sendable () async throws -> StreamDiagnosticsAppearance = {
            StreamDiagnosticsAppearance()
        },
        saveDiagnosticsAppearance: @escaping @Sendable (StreamDiagnosticsAppearance) async throws -> Void = {
            _ in
        },
        measureLight: @escaping @Sendable @MainActor (Bool) -> Void = { _ in
        },
        showMarker: @escaping @Sendable @MainActor (Bool) -> Void = { _ in
        },
        placeMarker: @escaping @Sendable @MainActor (BrightnessMarker) -> Void = { _ in
        },
        nudgeMarker: @escaping @Sendable @MainActor (BrightnessMarker.Nudge) -> Void = { _ in
        },
        glideMarker: @escaping @Sendable @MainActor (Double) -> Void = { _ in
        },
        coverStreamWithMenu: @escaping @Sendable @MainActor (Bool) -> Void = { _ in
        },
        updateAccessibility: @escaping @Sendable @MainActor (PlayStationAccessibilitySettings) -> Void = {
            _ in
        },
        joinInvitation: @escaping @Sendable @MainActor (String, String) -> Bool = { _, _ in
            false
        },
        openSavedData: @escaping @Sendable @MainActor () -> Bool = {
            false
        },
        runCouchCommand: @escaping @Sendable (CouchCommand) async -> Bool = { _ in
            true
        },
        handNavigation: @escaping @Sendable (UInt32?) async -> Void = { _ in
        },
        reloadControls: @escaping @Sendable (ControlsConfiguration) async -> Void = { _ in
        },
        couchInventory: @escaping @Sendable () async -> CouchInventory = {
            CouchInventory()
        },
        couchLights: @escaping @Sendable () -> CouchLights = {
            CouchLights()
        },
        microphoneStartPreference: @escaping @Sendable () async -> Bool = {
            false
        },
        requestMicrophonePermission: @escaping @Sendable () async -> Bool = {
            false
        },
        captureMicrophone: @escaping @Sendable (UUID) -> AsyncStream<MicrophoneCaptureEvent> = { _ in
            AsyncStream { continuation in
                continuation.yield(.failed(.streamUnavailable))
                continuation.finish()
            }
        },
        setMicrophoneMuted: @escaping @Sendable (UUID, Bool) async -> MicrophoneFailure? = { _, _ in
            .streamUnavailable
        },
        indicateMicrophone: @escaping @Sendable (Bool) async -> Void = { _ in
        },
        saveCapture: @escaping @Sendable (PendingCloudCapture, Bool) async -> Void = { _, _ in
        },
        resumeCaptures: @escaping @Sendable () async -> Void = {
        },
        invitations: @escaping @Sendable (ProfileID) async throws(CloudInvitationFailure)
            -> [CloudGameInvitation] = { _ throws(CloudInvitationFailure) in
                []
            },
        joinOnCloud: @escaping @Sendable (ProfileID, String) async throws(CloudInvitationFailure)
            -> Void = { _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        joinParty: @escaping @Sendable (ProfileID, String, HardwareID) async throws(CloudInvitationFailure)
            -> Void = { _, _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        joinOn: @escaping @Sendable (ProfileID, String, HardwareID) async throws(CloudInvitationFailure)
            -> Void = { _, _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        dismissNotifications: @escaping @Sendable (ProfileID, [String]) async throws(CloudInvitationFailure)
            -> Void = { _, _ throws(CloudInvitationFailure) in
            },
        psnAlerts: @escaping @Sendable (ProfileID) -> AsyncStream<PSNAlert> = { _ in
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        friends: @escaping @Sendable (ProfileID) async throws(CloudInvitationFailure)
            -> [PSNFriend] = { _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        ownGameSession: @escaping @Sendable (ProfileID, String, String) async throws(CloudInvitationFailure)
            -> OwnGameSession? = { _, _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        shareLink: @escaping @Sendable (ProfileID, String) async throws(CloudInvitationFailure)
            -> SessionLink = { _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            },
        inviteFriends: @escaping @Sendable (ProfileID, InvitationTarget, [String]) async
            throws(CloudInvitationFailure) -> Void = { _, _, _ throws(CloudInvitationFailure) in
                throw .unavailable
            }
    ) {
        self.start = start
        self.submitAccessCode = submitAccessCode
        self.keyboard = keyboard
        self.goHome = goHome
        self.selectDatacenter = selectDatacenter
        self.tune = tune
        self.leave = leave
        self.loadTuning = loadTuning
        self.saveTuning = saveTuning
        self.statisticsSamples = statisticsSamples
        self.applyVideoAnalysis = applyVideoAnalysis
        self.loadDiagnosticsAppearance = loadDiagnosticsAppearance
        self.saveDiagnosticsAppearance = saveDiagnosticsAppearance
        self.measureLight = measureLight
        self.showMarker = showMarker
        self.placeMarker = placeMarker
        self.nudgeMarker = nudgeMarker
        self.glideMarker = glideMarker
        self.coverStreamWithMenu = coverStreamWithMenu
        self.updateAccessibility = updateAccessibility
        self.joinInvitation = joinInvitation
        self.openSavedData = openSavedData
        self.runCouchCommand = runCouchCommand
        self.handNavigation = handNavigation
        self.reloadControls = reloadControls
        self.couchInventory = couchInventory
        self.couchLights = couchLights
        self.microphoneStartPreference = microphoneStartPreference
        self.requestMicrophonePermission = requestMicrophonePermission
        self.captureMicrophone = captureMicrophone
        self.setMicrophoneMuted = setMicrophoneMuted
        self.indicateMicrophone = indicateMicrophone
        self.saveCapture = saveCapture
        self.resumeCaptures = resumeCaptures
        self.invitations = invitations
        self.joinOnCloud = joinOnCloud
        self.joinParty = joinParty
        self.joinOn = joinOn
        self.dismissNotifications = dismissNotifications
        self.psnAlerts = psnAlerts
        self.friends = friends
        self.ownGameSession = ownGameSession
        self.shareLink = shareLink
        self.inviteFriends = inviteFriends
    }
}

extension StreamSessionClient: TestDependencyKey {
    /// Fails a test that starts or commands a stream without overriding the operation; the tuning loads a
    /// default configuration and discards saves, the diagnostics sample stream finishes at once with the
    /// default appearance, the player operations do nothing, the couch accepts every command and does nothing
    /// else, the microphone never starts and reports every capture or mute as unavailable, no invitation is
    /// listed and every other PlayStation Network request fails as unavailable, so tests never reach PSN, and
    /// no capture is saved.
    public static let testValue = StreamSessionClient()
}

extension DependencyValues {
    /// Starts stream sessions, commands the live one and reaches its player.
    public var streamSession: StreamSessionClient {
        get {
            self[StreamSessionClient.self]
        }
        set {
            self[StreamSessionClient.self] = newValue
        }
    }
}
