import Foundation
import Network

/// Tells the app when the network the device uses changes, such as a switch to another Wi-Fi network or a
/// hotspot, so connections opened on the old network are dropped instead of failing one request at a time.
@MainActor final class NetworkPathObserver {
    private let queue = DispatchQueue(label: "io.github.chiaki-ng.network-path")
    private var monitor: NWPathMonitor?
    private var last: String?
    private let changed: @MainActor () -> Void

    /// Creates an observer that is idle until it is started.
    ///
    /// - Parameter changed: Called each time the network changes; never for the first network seen.
    init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
    }

    /// Starts watching the network.
    func start() {
        guard monitor == nil else {
            return
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            Task { @MainActor in
                self?.observe(signature)
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    /// Stops watching the network.
    func stop() {
        monitor?.cancel()
        monitor = nil
        last = nil
    }

    private func observe(_ signature: String) {
        defer {
            last = signature
        }
        guard let last, last != signature else {
            return
        }
        changed()
    }

    private nonisolated static func signature(of path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map(\.name).joined(separator: ",")
        let gateways = path.gateways.map { "\($0)" }.joined(separator: ",")
        return "\(path.status) \(interfaces) \(gateways)"
    }
}
