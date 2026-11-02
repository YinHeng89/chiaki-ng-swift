import ChiakiClients
import ChiakiClientsLive
import ChiakiModels
import Dependencies
import ChiakiDiagnostics
import Foundation
import Video

extension CouchSessionEvent {
    /// Maps a couch event reported by the native player for pads 1 to 3, keeping the low 24 bits of
    /// the detail as the confirmed pad's light colour.
    /// - Parameters:
    ///   - kind: The native couch event.
    ///   - pad: The pad index the event is about.
    ///   - detail: Event data, the light colour for a confirmation.
    /// - Returns: `nil` for a pad outside 1 to 3 or an unknown event kind.
    init?(_ kind: CNCouchEvent, pad: Int, detail: Int) {
        guard (1 ... 3).contains(pad) else {
            return nil
        }
        let pad = UInt8(pad)
        switch kind {
        case .announced:
            self = .announced(pad: pad)
        case .confirmed:
            self = .confirmed(pad: pad, color: UInt32(truncatingIfNeeded: detail) & 0xffffff)
        case .dropped:
            self = .dropped(pad: pad)
        @unknown default:
            return nil
        }
    }

    /// Maps a refused seat for pads 1 to 3 to an unresolvable account event or a failed join event.
    /// - Parameters:
    ///   - pad: The pad index whose seat was refused.
    ///   - failure: Why the seat was refused, or `nil` when no failure was classified.
    /// - Returns: `nil` for a pad outside 1 to 3 or a missing failure.
    init?(seat pad: Int, refused failure: CouchFailure?) {
        guard (1 ... 3).contains(pad), let failure else {
            return nil
        }
        let pad = UInt8(pad)
        self = failure == .accountUnresolvable
            ? .accountUnresolvable(pad: pad)
            : .joinFailed(pad: pad, failure: failure)
    }
}

extension StreamSessionClient {
    /// Returns this client with the couch operations running couch commands, navigation overrides, control
    /// reloads, inventory and light queries against the native player and input of the stream that currently
    /// holds the lease.
    ///
    /// - Parameter coordinator: The input coordinator that hands menu navigation to another controller.
    /// - Returns: A copy whose couch operations reach the live stream.
    func seating(_ coordinator: SDLInputCoordinator) -> Self {
        var client = self
        client.runCouchCommand = { command in
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            return await MainActor.run {
                runNativeCouchCommand(command, leases: leases)
            }
        }
        client.handNavigation = { device in
            await MainActor.run {
                coordinator.overrideNavigation(device)
            }
        }
        client.reloadControls = { configuration in
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            await MainActor.run {
                NativeStreamPlayer.attachedInput(in: leases)?.reload(configuration: configuration)
            }
        }
        client.couchInventory = {
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            return await MainActor.run {
                NativeStreamPlayer.attachedInput(in: leases)?.inventory() ?? CouchInventory()
            }
        }
        client.couchLights = {
            @Dependency(\.streamLeases) var streamLeases
            let leases = streamLeases
            return MainActor.assumeIsolated {
                NativeStreamPlayer.attachedInput(in: leases)?.couchLights ?? CouchLights()
            }
        }
        return client
    }
}

@MainActor private func runNativeCouchCommand(_ command: CouchCommand, leases: StreamLeases) -> Bool {
    let player = (leases.current?.player as? NativeStreamPlayer)?.native
    switch command {
    case let .join(pad, controllerType, accountID):
        guard let player else {
            logCouchJoin("pad \(pad) was not sent: no stream is playing")
            return false
        }
        let accepted = player.couchJoinPad(Int(pad), controllerType: controllerType, accountID: accountID)
        if !accepted {
            logCouchJoin(
                "pad \(pad) with controller type \(controllerType) and "
                    + (accountID == nil
                        ? "no account"
                        : "an account") + " was not accepted by the stream"
            )
        }
        return accepted
    case .remove(let pad):
        guard let player else {
            return false
        }
        return player.couchRemovePad(Int(pad))
    case let .route(pad, device):
        NativeStreamPlayer.attachedInput(in: leases)?.route(pad: pad, device: device)
        return true
    case .assignPlayerOne(let device):
        NativeStreamPlayer.attachedInput(in: leases)?.assignPlayerOne(device)
        return true
    }
}

private func logCouchJoin(_ message: String) {
    @Dependency(\.logger) var logger
    logger.enqueue(.controllerDiagnostic("Couch join: " + message))
}
