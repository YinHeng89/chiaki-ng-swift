import ChiakiClients
import ChiakiClientsLive
import ChiakiFeatures
import ChiakiModels
import CoreGraphics
import Dependencies
import Foundation
import Video
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// What the stream menu and the diagnostics ask of the live player beyond its tuning: measuring light, the
/// brightness marker, telling PS5 cloud the menu covers the stream or the screen is off, the cloud's
/// Create presses and the cloud controller buttons.
///
/// The requests outlive any one player: each is kept and handed to the next player that attaches, as the
/// menu may ask before the player exists, and everything is switched off again when the player detaches.
/// While a player is attached the controls watch whether the displays sleep, the screen locks and the stream is
/// minimised or hidden, so a stream nobody can play reports `CloudSystemUIState.background`; a minimised or
/// hidden app keeps the game playing while background controller input is on. The composition root builds the
/// one instance over its input services' coordinator.
@MainActor
final class StreamPlayerControls {
    private let input: SDLInputCoordinator
    private weak var player: NativeStreamPlayer?
    private var marker = BrightnessMarker.centre
    private var markerShown = false
    private var measuresLight = false
    private var menuCoversStream = false
    private var screenOn = true
    private var visibilityObservers: [NSObjectProtocol] = []

    /// Creates the controls over the app's controller input.
    ///
    /// - Parameter input: The input coordinator whose cloud buttons the controls switch.
    init(input: SDLInputCoordinator) {
        self.input = input
    }

    /// Makes a player the one the controls drive and hands it every kept request.
    ///
    /// - Parameter player: The player that started a session.
    func attach(_ player: NativeStreamPlayer) {
        self.player = player
        player.native.measuresLight = measuresLight
        player.native.lightMarkerShown = markerShown
        watchVisibility()
        sendSystemUIState()
    }

    /// Forgets a player whose session ended and switches every request off.
    ///
    /// - Parameter player: The player whose session ended.
    func detach(_ player: NativeStreamPlayer) {
        guard self.player === player else {
            return
        }
        measuresLight = false
        markerShown = false
        menuCoversStream = false
        stopWatchingVisibility()
        input.systemButtonOpensStreamMenu = false
        input.createButtonCaptures = false
        self.player = nil
    }

    /// Hands the PS and Create buttons to a cloud stream.
    ///
    /// On PS5 cloud the PS button opens the stream menu, and Create presses go to the cloud console as gestures.
    /// On PS Now Create (Share) reaches the game; the PS button of a PS3 game reaches the stream, where the core
    /// turns it into the XMB toggle, while a PS4 game, whose cloud instance has no system menu, opens the stream
    /// menu instead.
    ///
    /// - Parameters:
    ///   - service: The cloud service the stream runs on.
    ///   - platform: The streamed game's platform, such as `PS4`.
    func captureCloudButtons(for service: CloudService, platform: String) {
        let ps5 = service == .psCloud
        input.systemButtonOpensStreamMenu = ps5 || platform.uppercased() != "PS3"
        input.createButtonCaptures = ps5
    }

    /// Switches the renderer's light measurement on or off.
    ///
    /// - Parameter measures: Whether light is measured.
    func measureLight(_ measures: Bool) {
        measuresLight = measures
        player?.native.measuresLight = measures
    }

    /// Shows or hides the brightness marker on the heatmap.
    ///
    /// - Parameter shown: Whether the marker is shown.
    func showMarker(_ shown: Bool) {
        markerShown = shown
        player?.native.lightMarkerShown = shown
    }

    /// Places the brightness marker.
    ///
    /// - Parameter point: Where it points.
    func placeMarker(_ point: BrightnessMarker) {
        marker = point
        player?.native.setLightMarkerX(point.x, y: point.y)
    }

    /// Moves the brightness marker one step, unless the stick is gliding it.
    ///
    /// - Parameter nudge: The direction.
    func nudgeMarker(_ nudge: BrightnessMarker.Nudge) {
        let stick = input.navigationStick
        guard !BrightnessMarker.stickDeflected(dx: stick.dx, dy: stick.dy) else {
            return
        }
        placeMarker(currentMarker.nudged(nudge))
    }

    /// Glides the brightness marker by the menu controller's left stick.
    ///
    /// - Parameter seconds: How long since the last glide.
    func glideMarker(seconds: Double) {
        let stick = input.navigationStick
        let moved = currentMarker.glided(dx: stick.dx, dy: stick.dy, seconds: seconds)
        guard moved != currentMarker else {
            return
        }
        placeMarker(moved)
    }

    /// Tells PS5 cloud whether the stream menu covers the stream.
    ///
    /// - Parameter covers: Whether the menu is open.
    func coverStreamWithMenu(_ covers: Bool) {
        menuCoversStream = covers
        sendSystemUIState()
    }

    /// Tells PS5 cloud again what the client's screen shows after background controller input was switched,
    /// since a minimised or hidden stream is only playable while it is on.
    func backgroundInputChanged() {
        sendSystemUIState()
    }

    /// Hands changed PlayStation accessibility settings to the attached player, with every device default
    /// filled in: a cloud stream that has not launched yet starts with them, a playing PS5 cloud stream sends
    /// them on, and other streams ignore them.
    ///
    /// - Parameter settings: The saved settings.
    func updateAccessibility(_ settings: PlayStationAccessibilitySettings) {
        guard let player else {
            return
        }
        player.request(settings.resolved(using: PlayStationAccessibilitySystemDefaults.current))
        player.native.updateCloudAccessibility()
    }

    /// Sends a Create press to the cloud console.
    ///
    /// - Parameter press: The press.
    func pressCreate(_ press: CreateButtonGesture.Press) {
        let code = switch press {
        case .singleTap:
            0
        case .doubleTap:
            1
        case .longPress:
            2
        }
        _ = player?.native.pressCreate(code)
    }

    /// Has the playing PS5 cloud or PS Now stream join a game invitation.
    ///
    /// - Parameters:
    ///   - invitationID: The invitation's id.
    ///   - session: The invited game session's id.
    /// - Returns: Whether a playing cloud stream queued the invitation.
    func joinInvitation(_ invitationID: String, session: String) -> Bool {
        player?.native.joinInvitation(invitationID, session: session) ?? false
    }

    /// Has the playing PS Now stream open the cloud PS4's Application Saved Data Management screen.
    ///
    /// - Returns: Whether a playing PS Now stream queued the request.
    func openSavedData() -> Bool {
        player?.native.openSavedData() ?? false
    }

    private func sendSystemUIState() {
        let state = CloudSystemUIState(
            menuCoversStream: menuCoversStream,
            screenOn: screenOn,
            appHidden: appHidden,
            backgroundInput: input.controlsConfiguration.backgroundInput
        )
        player?.native.systemUIState = switch state {
        case .game:
            .game
        case .overlaid:
            .overlaid
        case .background:
            .background
        }
    }

    private func watchVisibility() {
        guard visibilityObservers.isEmpty else {
            return
        }
        screenOn = true
        for (center, name) in Self.visibilityChanges {
            let observer = center
                .addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let change = notification.name
                    MainActor.assumeIsolated {
                        self?.visibilityChanged(change)
                    }
                }
            visibilityObservers.append(observer)
        }
    }

    private func stopWatchingVisibility() {
        for (observer, center) in zip(visibilityObservers, Self.visibilityChanges.map(\.0)) {
            center.removeObserver(observer)
        }
        visibilityObservers = []
        screenOn = true
    }

    private func visibilityChanged(_ change: Notification.Name) {
        if Self.screenOffChanges.contains(change) {
            screenOn = false
        } else if Self.screenOnChanges.contains(change) {
            screenOn = true
        }
        sendSystemUIState()
    }

    #if os(macOS)
        private static let screenOffChanges: Set<Notification.Name> = [
            NSWorkspace.screensDidSleepNotification,
            Notification.Name("com.apple.screenIsLocked")
        ]

        private static let screenOnChanges: Set<Notification.Name> = [
            NSWorkspace.screensDidWakeNotification,
            Notification.Name("com.apple.screenIsUnlocked")
        ]

        private static let visibilityChanges: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")),
            (NotificationCenter.default, NSApplication.didHideNotification),
            (NotificationCenter.default, NSApplication.didUnhideNotification),
            (NotificationCenter.default, NSWindow.didMiniaturizeNotification),
            (NotificationCenter.default, NSWindow.didDeminiaturizeNotification)
        ]

        private var appHidden: Bool {
            NSApplication.shared.isHidden || player?.native.view.window?.isMiniaturized == true
        }
    #else
        private static let screenOffChanges: Set<Notification.Name> = []

        private static let screenOnChanges: Set<Notification.Name> = []

        private static let visibilityChanges: [(NotificationCenter, Notification.Name)] = [
            (NotificationCenter.default, UIApplication.didEnterBackgroundNotification),
            (NotificationCenter.default, UIApplication.didBecomeActiveNotification)
        ]

        private var appHidden: Bool {
            UIApplication.shared.applicationState == .background
        }
    #endif

    private var currentMarker: BrightnessMarker {
        guard let point = player?.native.lightMarker else {
            return marker
        }
        return BrightnessMarker(x: point.x, y: point.y)
    }
}

extension StreamSessionClient {
    /// Returns this client with the player operations over the app's player controls and the diagnostics
    /// polling the leased native player and reading and writing the overlay appearance through the account
    /// settings store.
    ///
    /// - Parameter controls: The one set of player controls.
    /// - Returns: A copy whose player and diagnostics operations reach the live player.
    func controlling(_ controls: StreamPlayerControls) -> Self {
        var client = self
        client.measureLight = { measures in
            controls.measureLight(measures)
        }
        client.showMarker = { shown in
            controls.showMarker(shown)
        }
        client.placeMarker = { point in
            controls.placeMarker(point)
        }
        client.nudgeMarker = { nudge in
            controls.nudgeMarker(nudge)
        }
        client.glideMarker = { seconds in
            controls.glideMarker(seconds: seconds)
        }
        client.coverStreamWithMenu = { covers in
            controls.coverStreamWithMenu(covers)
        }
        client.updateAccessibility = { settings in
            controls.updateAccessibility(settings)
        }
        client.joinInvitation = { invitation, session in
            controls.joinInvitation(invitation, session: session)
        }
        client.openSavedData = {
            controls.openSavedData()
        }
        client.statisticsSamples = {
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            return AsyncStream { continuation in
                let task = Task { @MainActor in
                    while !Task.isCancelled {
                        let player = leases.current?.player as? NativeStreamPlayer
                        continuation.yield(StreamStatisticsSample(
                            statistics: player?.statistics,
                            uptime: ProcessInfo.processInfo.systemUptime
                        ))
                        try? await Task.sleep(for: PacketLossWarning.sampleInterval)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        client.applyVideoAnalysis = { mode in
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            (leases.current?.player as? NativeStreamPlayer)?.applyVideoAnalysis(mode)
        }
        client.loadDiagnosticsAppearance = {
            @Dependency(\.accountService) var accountService
            return try await accountService.storage().settings.value(SettingKeys.streamDiagnostics)
        }
        client.saveDiagnosticsAppearance = { appearance in
            @Dependency(\.accountService) var accountService
            return try await accountService.storage().settings.save(
                appearance,
                for: SettingKeys.streamDiagnostics
            )
        }
        return client
    }
}
