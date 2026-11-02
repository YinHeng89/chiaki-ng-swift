import ChiakiModels
import Foundation

/// Lights every seated controller's lightbar and player number for the stream, restores them afterwards, and
/// shares the lightbar choices and player one's colour with couch guests.
@MainActor
final class LightbarController {
    private let environment: InputEnvironment
    private var plan = ControllerLightPlan()
    private var ledger = ControllerLightLedger()
    private var events: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var lastPublished: CouchLights?
    private var originalPlayers: [UInt32: Int] = [:]
    private var ended = false

    /// Creates the controller.
    ///
    /// - Parameters:
    ///   - environment: The controllers it lights and where it reports.
    ///   - configured: The saved lightbar choices.
    init(environment: InputEnvironment, configured: ControllerLightbars) {
        self.environment = environment
        plan.lightbars = configured
    }

    /// The lightbar choices the stream uses.
    ///
    /// - Parameters:
    ///   - shown: The choices the app currently shows, such as an unsaved draft.
    ///   - configured: The saved choices.
    /// - Returns: The shown choices when there are any, otherwise the saved ones.
    nonisolated static func chosen(shown: ControllerLightbars?,
                                   configured: ControllerLightbars) -> ControllerLightbars {
        shown ?? configured
    }

    /// The controller on each pad whose lights the stream owns.
    ///
    /// - Parameters:
    ///   - playerOne: Player one's controller.
    ///   - seats: The couch seats.
    ///   - live: Whether the stream still runs.
    /// - Returns: The controllers by pad; none once the stream has stopped.
    nonisolated static func devices(
        playerOne: ControllerDevice?,
        seats: [UInt8: SeatedController],
        live: Bool
    ) -> [UInt8: ControllerDevice] {
        var devices: [UInt8: ControllerDevice] = [:]
        guard live else {
            return devices
        }
        if let playerOne {
            devices[0] = playerOne
        }
        for (pad, seat) in seats {
            devices[pad] = seat.device
        }
        return devices
    }

    /// The lights shared with couch guests.
    var couchLights: CouchLights {
        CouchLights(
            lightbars: plan.lightbars,
            playerOne: plan.playerOneColor,
            revision: revision
        )
    }

    /// Takes the lightbar choices the app currently shows, falling back to the saved ones.
    ///
    /// - Parameter configured: The saved choices.
    func adopt(configured: ControllerLightbars) {
        plan.lightbars = Self.chosen(shown: environment.lights.lightbars, configured: configured)
    }

    /// Records the colour the game set for a pad.
    ///
    /// - Parameters:
    ///   - pad: The pad.
    ///   - color: The colour as `0xRRGGBB`.
    func setGameColor(pad: UInt8, color: UInt32) {
        plan.gameColors[pad] = color & ControllerLightbar.maximumRGB
    }

    /// Forgets the game's colour for a pad nobody plays on.
    ///
    /// - Parameter pad: The pad.
    func forgetGameColor(pad: UInt8) {
        plan.gameColors[pad] = nil
    }

    /// Lights exactly the given controllers and shares the result.
    ///
    /// - Parameter devices: The controllers by pad.
    func show(_ devices: [UInt8: ControllerDevice]) {
        let timing = SlowStep("updating controller lights and player number")
        defer {
            timing.finish()
        }
        plan.devices = devices
        apply(ledger.reconcile(to: plan.targets()))
        publish()
    }

    /// Stops sharing lights once the stream has stopped.
    func end() {
        ended = true
    }

    /// Cancels the latest pending share.
    func stopEvents() {
        events?.cancel()
        events = nil
    }

    private func apply(_ changes: ControllerLightChanges) {
        guard !changes.isEmpty else {
            return
        }
        let backend = environment.backend
        for (id, player) in changes.players {
            if originalPlayers[id] == nil {
                originalPlayers[id] = backend.playerIndex(id)
            }
            backend.player(id, index: player)
        }
        for (id, rgb) in changes.colors {
            backend.light(id, rgb: rgb)
        }
        for id in changes.defaults {
            backend.defaultLight(id)
        }
        for (id, recoloured) in changes.released {
            backend.player(id, index: originalPlayers.removeValue(forKey: id) ?? -1)
            if recoloured {
                backend.defaultLight(id)
            }
        }
    }

    private func publish() {
        guard !ended else {
            return
        }
        let published = CouchLights(lightbars: plan.lightbars, playerOne: plan.playerOneColor)
        guard published != lastPublished else {
            return
        }
        lastPublished = published
        revision += 1
        let lights = couchLights
        let previous = events
        let report = environment.report
        events = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, !self.ended else {
                return
            }
            await report(.lights(lights))
        }
    }
}
