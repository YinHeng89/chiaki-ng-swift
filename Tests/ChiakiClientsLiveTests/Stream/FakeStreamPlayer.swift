import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import Foundation

@MainActor
final class FakeStreamPlayer: StreamPlayer {
    final class View {
    }

    let view = View()
    var restRefused = false
    var acceptsLoginPIN = true
    private(set) var calls: [String] = []
    private var receive: (@MainActor (PlayerSignal) -> Void)?
    private var ending: (@MainActor @Sendable (Int) -> Void)?

    var surface: StreamSurface {
        StreamSurface(view)
    }

    var connected: Bool {
        receive != nil
    }

    func connect(_ receive: @escaping @MainActor (PlayerSignal) -> Void) {
        self.receive = receive
    }

    func disconnect() {
        receive = nil
    }

    func fire(_ signal: PlayerSignal) {
        receive?(signal)
    }

    func begin(_ ending: @escaping @MainActor @Sendable (Int) -> Void) {
        calls.append("start")
        self.ending = ending
    }

    func end(_ code: Int = 0) {
        let ending = ending
        self.ending = nil
        ending?(code)
    }

    func stop() {
        calls.append("stop")
        end()
    }

    func stopWithRest() {
        calls.append("rest")
        end()
    }

    func stopForSleep() {
        calls.append("sleep")
        end()
    }

    func stopForSleepWithRest() {
        calls.append("sleep rest")
        end()
    }

    func submitLoginPIN(_ code: StreamAccessCode) async -> Bool {
        calls.append("pin \(code.digits)")
        return acceptsLoginPIN
    }

    func submitControllerPasscode(_ code: StreamAccessCode, pad: UInt8) -> Bool {
        calls.append("passcode \(pad)")
        return true
    }

    func goHome() -> Bool {
        calls.append("home")
        return true
    }

    func send(_ command: ConsoleKeyboardCommand) -> Bool {
        calls.append("keyboard")
        return true
    }

    func selectDatacenter(_ name: String) -> Bool {
        calls.append("datacenter \(name)")
        return true
    }

    func apply(_ tuning: StreamTuningConfiguration) {
        calls.append("tune")
    }
}

@MainActor
final class FakeStreamLauncher: StreamLauncher {
    let player = FakeStreamPlayer()
    var failure: StreamFailure?
    private(set) var observed: [PlayerSignal] = []
    private(set) var session: LiveStreamSession?
    private(set) var launched = 0
    private var started: CheckedContinuation<Void, Never>?
    private var isRunning = false

    func launch(_ source: StreamSource, opening opener: StreamSessionOpener) async throws(StreamFailure) {
        launched += 1
        let session = opener.open(player)
        self.session = session
        session.relay.observe { [weak self] signal in
            self?.observed.append(signal)
        }
        let ending: Int? = await session.run(rest: source.kind == .console) { ending in
            self.player.begin(ending)
            self.isRunning = true
            self.started?.resume()
            self.started = nil
        }
        isRunning = false
        if let failure, ending != nil {
            throw failure
        }
    }

    func waitUntilRunning() async {
        guard !isRunning else {
            return
        }
        await withCheckedContinuation { continuation in
            started = continuation
        }
    }
}
