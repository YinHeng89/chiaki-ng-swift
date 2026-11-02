import ChiakiClients
import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

private final class MicrophoneProbe: Sendable {
    let indicated = LockIsolated<[Bool]>([])
    let muted = LockIsolated<[Bool]>([])
    let captures = LockIsolated<[UUID: AsyncStream<MicrophoneCaptureEvent>.Continuation]>([:])

    func emit(_ operation: UUID, _ event: MicrophoneCaptureEvent) async {
        for _ in 0..<1000 where captures.value[operation] == nil {
            await Task.yield()
        }
        _ = captures.value[operation]?.yield(event)
    }

    func client(
        startPreference: Bool = false,
        permission: Bool = true,
        muteFailure: MicrophoneFailure? = nil,
        on base: StreamSessionClient
    ) -> StreamSessionClient {
        var client = base
        client.microphoneStartPreference = {
            startPreference
        }
        client.requestMicrophonePermission = {
            permission
        }
        client.captureMicrophone = { [captures] operation in
            AsyncStream { continuation in
                captures.withValue {
                    $0[operation] = continuation
                }
            }
        }
        client.setMicrophoneMuted = { [muted] _, value in
            muted.withValue {
                $0.append(value)
            }
            return muteFailure
        }
        client.indicateMicrophone = { [indicated] lit in
            indicated.withValue {
                $0.append(lit)
            }
        }
        return client
    }
}

private let session = UUID()

@MainActor @Test func microphoneStartsWithTheStreamWhenThePreferenceIsOn() async {
    let probe = MicrophoneProbe()
    let store = TestStore(initialState: MicrophoneReducer.State()) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(startPreference: true, on: $0.streamSession)
    }
    await store.send(.streamStarted(session)) {
        $0.availability = .available(session)
    }
    await store.receive(.startPreferenceLoaded(session, true)) {
        $0.machine = MicrophoneMachine(phase: .requestingPermission(UUID(0)))
    }
    await store.receive(.permissionResolved(UUID(0), true)) {
        $0.machine = MicrophoneMachine(phase: .connecting(UUID(0)))
    }
    await probe.emit(UUID(0), .started)
    await store.receive(.capture(UUID(0), .started)) {
        $0.machine = MicrophoneMachine(phase: .live(UUID(0), muted: false))
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .live(UUID(0), muted: true))
    }
    await store.receive(.muteApplied(UUID(0), muted: true, failure: nil))
    await store.send(.streamEnded) {
        $0.availability = .unavailable
        $0.machine = MicrophoneMachine()
    }
    #expect(probe.muted.value == [true])
    #expect(probe.indicated.value == [true, false, true, false])
}

@MainActor @Test func microphoneStaysOffWhenThePreferenceIsOff() async {
    let probe = MicrophoneProbe()
    let store = TestStore(initialState: MicrophoneReducer.State()) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(startPreference: false, on: $0.streamSession)
    }
    await store.send(.streamStarted(session)) {
        $0.availability = .available(session)
    }
    await store.receive(.startPreferenceLoaded(session, false))
    await store.send(.startPreferenceLoaded(UUID(), true))
    await store.send(.streamEnded) {
        $0.availability = .unavailable
    }
    #expect(probe.indicated.value == [true, false])
}

@MainActor @Test func microphoneToggleIsIgnoredWithoutAStream() async {
    let probe = MicrophoneProbe()
    let store = TestStore(initialState: MicrophoneReducer.State()) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(on: $0.streamSession)
    }
    await store.send(.toggle)
    #expect(probe.indicated.value.isEmpty)
}

@MainActor @Test func microphoneIgnoresAPermissionAnswerAfterTheStreamEnds() async {
    var state = MicrophoneReducer.State()
    state.availability = .available(session)
    state.machine = MicrophoneMachine(phase: .requestingPermission(UUID(0)))
    let probe = MicrophoneProbe()
    let store = TestStore(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(on: $0.streamSession)
    }
    await store.send(.streamEnded) {
        $0.availability = .unavailable
        $0.machine = MicrophoneMachine()
    }
    await store.send(.permissionResolved(UUID(0), true))
    await store.send(.capture(UUID(0), .started))
    #expect(probe.captures.value.isEmpty)
}

@MainActor @Test func microphoneIgnoresEventsFromAnEarlierConnection() async {
    let probe = MicrophoneProbe()
    var state = MicrophoneReducer.State()
    state.availability = .available(session)
    let store = TestStore(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(on: $0.streamSession)
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .requestingPermission(UUID(0)))
    }
    await store.receive(.permissionResolved(UUID(0), true)) {
        $0.machine = MicrophoneMachine(phase: .connecting(UUID(0)))
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine()
    }
    await probe.emit(UUID(0), .started)
    await store.send(.capture(UUID(0), .started))
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .requestingPermission(UUID(2)))
    }
    await store.receive(.permissionResolved(UUID(2), true)) {
        $0.machine = MicrophoneMachine(phase: .connecting(UUID(2)))
    }
    await store.send(.capture(UUID(0), .failed(.consoleRejected)))
    await probe.emit(UUID(2), .started)
    await store.receive(.capture(UUID(2), .started)) {
        $0.machine = MicrophoneMachine(phase: .live(UUID(2), muted: false))
    }
    await store.send(.capture(UUID(0), .failed(.interrupted("old"))))
    await store.send(.streamEnded) {
        $0.availability = .unavailable
        $0.machine = MicrophoneMachine()
    }
    #expect(probe.indicated.value == [false])
}

@MainActor @Test func microphoneCaptureFailureLightsTheMuteIndicator() async {
    let probe = MicrophoneProbe()
    var state = MicrophoneReducer.State()
    state.availability = .available(session)
    let store = TestStore(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(on: $0.streamSession)
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .requestingPermission(UUID(0)))
    }
    await store.receive(.permissionResolved(UUID(0), true)) {
        $0.machine = MicrophoneMachine(phase: .connecting(UUID(0)))
    }
    await probe.emit(UUID(0), .started)
    await store.receive(.capture(UUID(0), .started)) {
        $0.machine = MicrophoneMachine(phase: .live(UUID(0), muted: false))
    }
    await probe.emit(UUID(0), .failed(.interrupted("unplugged")))
    await store.receive(.capture(UUID(0), .failed(.interrupted("unplugged")))) {
        $0.machine = MicrophoneMachine(phase: .failed(.interrupted("unplugged")))
    }
    #expect(probe.indicated.value == [false, true])
}

@MainActor @Test func microphoneDeniedPermissionLeavesItOff() async {
    let probe = MicrophoneProbe()
    var state = MicrophoneReducer.State()
    state.availability = .available(session)
    let store = TestStore(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(permission: false, on: $0.streamSession)
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .requestingPermission(UUID(0)))
    }
    await store.receive(.permissionResolved(UUID(0), false)) {
        $0.machine = MicrophoneMachine(phase: .denied)
    }
    #expect(probe.captures.value.isEmpty)
}

@MainActor @Test func microphoneMuteRejectionFailsTheMicrophone() async {
    let probe = MicrophoneProbe()
    var state = MicrophoneReducer.State()
    state.availability = .available(session)
    state.machine = MicrophoneMachine(phase: .live(UUID(9), muted: false))
    let store = TestStore(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession = probe.client(muteFailure: .consoleRejected, on: $0.streamSession)
    }
    await store.send(.toggle) {
        $0.machine = MicrophoneMachine(phase: .live(UUID(9), muted: true))
    }
    await store.receive(.muteApplied(UUID(9), muted: true, failure: .consoleRejected)) {
        $0.machine = MicrophoneMachine(phase: .failed(.consoleRejected))
    }
}

@MainActor @Test func streamingStartsAndEndsTheMicrophoneWithPlayback() async {
    let probe = MicrophoneProbe()
    let console = RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5)
    let store = StreamSessionCalls().store {
        $0.streamSession = probe.client(on: $0.streamSession)
    }
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    let id = UUID(0)
    await store.send(.event(StreamSessionID(uuid: id), .firstFrame))
    #expect(store.state.microphone.availability == .available(id))
    await store.send(.ended(StreamSessionID(uuid: id)))
    #expect(store.state.microphone.availability == .unavailable)
}
