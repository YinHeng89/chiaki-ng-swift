#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import ComposableArchitecture
    import Foundation
    import Testing

    private let identity = KakusanIdentity(
        publicKey: KakusanFixture.key(1),
        fingerprint: KakusanFixture.fingerprint(1)
    )
    private let alex = KakusanFixture.remembered(2, "Alex")
    private let sam = KakusanFixture.remembered(3, "Sam")

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    @MainActor
    private func settingsStore(
        _ state: KakusanSettingsFeature.State = KakusanSettingsFeature.State(),
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<KakusanSettingsFeature> {
        TestStore(initialState: state) {
            KakusanSettingsFeature()
        } withDependencies: {
            $0.kakusan.nickname = KakusanFixture.nickname
            $0.kakusan.useStunServers = { _ in
                .success(())
            }
            $0.kakusan.disarm = {}
            $0.kakusan.loadSettings = {
                KakusanSettings()
            }
            $0.uuid = .incrementing
            $0.kakusan.identity = { identity }
            $0.kakusan.peers = { [alex, sam] }
            $0.kakusan.loadSettings = { KakusanSettings() }
            configure(&$0)
        }
    }

    @MainActor
    private func loaded(
        _ store: TestStoreOf<KakusanSettingsFeature>,
        _ stored: KakusanSettings = KakusanSettings()
    ) async {
        await store.send(.load) {
            $0.identity = .loading(id(0))
            $0.stun = .loading(id(1))
            $0.tuning = .loading(id(1))
            $0.peers = .loading(id(2))
        }
        await store.receive(.identityLoaded(id(0), identity)) {
            $0.identity = .ready(identity)
        }
        await store.receive(.settingsLoaded(id(1), stored)) {
            $0.configuration = stored
            $0.stunDraft = stored.stunServers.joined(separator: "\n")
            $0.stun = .ready
            $0.tuningDraft = KakusanTuningDraft(stored.tuning)
            $0.tuning = .ready
        }
        await store.receive(.peersLoaded(id(2), [alex, sam])) {
            $0.peers = .ready([alex, sam])
        }
    }

    @MainActor @Test func settingsShowThisDeviceAndValidateStunServers() async {
        let saved = LockIsolated<[KakusanSettings]>([])
        let store = settingsStore {
            $0.kakusan.saveSettings = { value in saved.withValue { $0.append(value) } }
        }
        await loaded(store)
        await store.send(.binding(.set(\.stunDraft, "stun.example:3478\nnot valid"))) {
            $0.stunDraft = "stun.example:3478\nnot valid"
        }
        await store.send(.saveStun) {
            $0.stun = .invalid
        }
        await store.send(.binding(.set(\.stunDraft, ""))) {
            $0.stunDraft = ""
            $0.stun = .ready
        }
        await store.send(.saveStun) {
            $0.stun = .saving(id(3))
        }
        await store.receive(.stunSaved(id(3), KakusanSettings(stunServers: []))) {
            $0.configuration = KakusanSettings(stunServers: [])
            $0.stun = .ready
        }
        await store.send(.restoreDefaultStun) {
            $0.stun = .saving(id(4))
        }
        await store.receive(.stunSaved(id(4), KakusanSettings())) {
            $0.configuration = KakusanSettings()
            $0.stunDraft = ""
            $0.stun = .ready
        }
        #expect(saved.value == [KakusanSettings(stunServers: []), KakusanSettings()])
    }

    @MainActor @Test func identityFailureIsReportedWithoutBlockingTheRest() async {
        let store = settingsStore {
            $0.kakusan.identity = { throw KakusanError.cryptoUnavailable }
            $0.kakusan.peers = { throw KakusanError.internal }
        }
        await store.send(.load) {
            $0.identity = .loading(id(0))
            $0.stun = .loading(id(1))
            $0.tuning = .loading(id(1))
            $0.peers = .loading(id(2))
        }
        await store.receive(.identityFailed(id(0))) {
            $0.identity = .failed
        }
        await store.receive(.settingsLoaded(id(1), KakusanSettings())) {
            $0.stunDraft = ""
            $0.stun = .ready
            $0.tuning = .ready
        }
        await store.receive(.peersFailed(id(2))) {
            $0.peers = .failed
        }
    }

    @MainActor @Test func renamingToATakenNameIsRefusedUntilChanged() async {
        let store = settingsStore {
            $0.kakusan.rename = { key, name in
                name == "Alex"
                    ? .nicknameTaken(alex)
                    : .saved(KakusanPeer(
                        publicKey: key, fingerprint: sam.fingerprint, nickname: name,
                        firstVerifiedAt: sam.firstVerifiedAt, lastSeenAt: sam.lastSeenAt
                    ))
            }
        }
        await loaded(store)
        let samwise = KakusanPeer(
            publicKey: sam.publicKey, fingerprint: sam.fingerprint, nickname: "Samwise",
            firstVerifiedAt: sam.firstVerifiedAt, lastSeenAt: sam.lastSeenAt
        )
        await store.send(.startRename(sam.publicKey)) {
            $0.rename = KakusanRememberFeature.State(
                subject: .remembered(sam),
                name: "Sam",
                normalised: "Sam"
            )
        }
        await store.send(.rename(.presented(.binding(.set(\.name, "Alex"))))) {
            $0.rename?.name = "Alex"
            $0.rename?.normalised = "Alex"
        }
        await store.send(.rename(.presented(.view(.controlActivated(.save))))) {
            $0.rename?.phase = .saving(id(3))
            $0.rename?.controls.select(.save)
        }
        await store.receive(.rename(.presented(.saved(id(3), .nicknameTaken(alex))))) {
            $0.rename?.phase = .conflict(alex)
            $0.rename?.controls.show([[.name], [.cancel, .replace, .save]], preferring: .replace)
        }
        await store.send(.rename(.presented(.view(.controlActivated(.replace))))) {
            $0.rename?.controls.select(.replace)
        }
        await store.send(.rename(.presented(.binding(.set(\.name, "Samwise"))))) {
            $0.rename?.name = "Samwise"
            $0.rename?.normalised = "Samwise"
            $0.rename?.phase = .editing
            $0.rename?.controls.show([[.name], [.cancel, .save]])
        }
        await store.send(.rename(.presented(.view(.nameSubmitted)))) {
            $0.rename?.controls.select(.save)
            $0.rename?.phase = .saving(id(4))
        }
        await store.receive(.rename(.presented(.saved(id(4), .saved(samwise)))))
        await store.receive(.rename(.presented(.delegate(.finished(samwise))))) {
            $0.rename = nil
            $0.peers = .loading(id(5))
        }
        await store.receive(.peersLoaded(id(5), [alex, sam])) {
            $0.peers = .ready([alex, sam])
        }
    }

    @MainActor @Test func forgettingADeviceNeedsConfirmation() async {
        let forgotten = LockIsolated<[KakusanPublicKey]>([])
        let store = settingsStore {
            $0.kakusan.forget = { key in forgotten.withValue { $0.append(key) } }
        }
        await loaded(store)
        await store.send(.requestForget(alex.publicKey)) {
            $0.forget = .confirming(alex)
        }
        await store.send(.cancelForget) {
            $0.forget = nil
        }
        #expect(forgotten.value.isEmpty)
        await store.send(.requestForget(alex.publicKey)) {
            $0.forget = .confirming(alex)
        }
        await store.send(.confirmForget) {
            $0.forget = .removing(alex, id(3))
        }
        await store.receive(.forgotten(id(3))) {
            $0.forget = nil
            $0.peers = .loading(id(4))
        }
        await store.receive(.peersLoaded(id(4), [alex, sam])) {
            $0.peers = .ready([alex, sam])
        }
        #expect(forgotten.value == [alex.publicKey])
        await store.send(.requestForget(KakusanFixture.key(77)))
    }

    private let customServers = ["stun.example:3478"]

    private var customTuning: KakusanMediaTuning {
        var value = KakusanMediaTuning()
        value.queueAgeMinimumMs = 150
        value.keyframeIntervalMs = 2000
        return value
    }

    private let customSettings = KakusanSettings(stunServers: customServers, tuning: customTuning)

    @MainActor @Test func loadingSettingsFillsTheTuningDraft() async {
        let store = settingsStore {
            $0.kakusan.loadSettings = { customSettings }
        }
        await loaded(store, customSettings)
        #expect(store.state.tuningDraft[.queueAgeMinimumMs] == "150")
        #expect(store.state.tuningDraft[.keyframeIntervalMs] == "2000")
        #expect(store.state.tuningDraft[.queuePackets] == "8192")
        #expect(!store.state.tuningChanged)
        #expect(store.state.tuningSaveBlocked)
    }

    @MainActor @Test func invalidTuningInputIsShownAndBlocksSaving() async {
        let saved = LockIsolated<[KakusanSettings]>([])
        let store = settingsStore {
            $0.kakusan.saveSettings = { value in saved.withValue { $0.append(value) } }
        }
        await loaded(store)
        await store.send(.editTuning(.queueAgeMaximumMs, "5000")) {
            $0.tuningDraft[.queueAgeMaximumMs] = "5000"
            $0.tuning = .invalid
        }
        #expect(store.state.tuningDraft.value(.queueAgeMaximumMs) == nil)
        #expect(store.state.tuningDraft.value(.queueAgeMinimumMs) == 100)
        #expect(store.state.tuningSaveBlocked)
        await store.send(.saveTuning)
        await store.send(.editTuning(.queueAgeMaximumMs, "")) {
            $0.tuningDraft[.queueAgeMaximumMs] = ""
        }
        await store.send(.editTuning(.queueAgeMaximumMs, "abc")) {
            $0.tuningDraft[.queueAgeMaximumMs] = "abc"
        }
        await store.send(.saveTuning)
        await store.send(.editTuning(.queueAgeMaximumMs, "400")) {
            $0.tuningDraft[.queueAgeMaximumMs] = "400"
            $0.tuning = .ready
        }
        #expect(store.state.tuningChanged)
        #expect(!store.state.tuningSaveBlocked)
        #expect(saved.value.isEmpty)
    }

    @MainActor @Test func savingTuningPersistsItAndKeepsTheStunServers() async {
        let saved = LockIsolated<[KakusanSettings]>([])
        let (gate, release) = AsyncStream<Void>.makeStream()
        let store = settingsStore {
            $0.kakusan.loadSettings = { customSettings }
            $0.kakusan.saveSettings = { value in
                saved.withValue { $0.append(value) }
                for await _ in gate {
                    break
                }
            }
        }
        await loaded(store, customSettings)
        var edited = customTuning
        edited.queueKilobytes = 8192
        edited.startupGraceMs = 0
        await store.send(.editTuning(.queueKilobytes, " 8192 ")) {
            $0.tuningDraft[.queueKilobytes] = " 8192 "
        }
        await store.send(.editTuning(.startupGraceMs, "0")) {
            $0.tuningDraft[.startupGraceMs] = "0"
        }
        await store.send(.saveTuning) {
            $0.tuning = .saving(id(3))
        }
        await store.send(.binding(.set(\.stunDraft, "stun.other:3478"))) {
            $0.stunDraft = "stun.other:3478"
        }
        await store.send(.saveStun)
        await store.send(.restoreDefaultTuning)
        release.yield()
        await store.receive(.tuningSaved(id(3), edited)) {
            $0.configuration.tuning = edited
            $0.tuningDraft = KakusanTuningDraft(edited)
            $0.tuning = .ready
        }
        let other = KakusanSettings(stunServers: ["stun.other:3478"], tuning: edited)
        await store.send(.editTuning(.queuePackets, "4096")) {
            $0.tuningDraft[.queuePackets] = "4096"
        }
        await store.send(.saveStun) {
            $0.stun = .saving(id(4))
        }
        await store.send(.saveTuning)
        release.yield()
        await store.receive(.stunSaved(id(4), other)) {
            $0.configuration.stunServers = other.stunServers
            $0.stun = .ready
        }
        #expect(store.state.tuningDraft[.queuePackets] == "4096")
        #expect(saved.value == [KakusanSettings(stunServers: customServers, tuning: edited), other])
    }

    @MainActor @Test func tuningSaveClampsTheLongestQueueWaitToTheShortest() async {
        let saved = LockIsolated<[KakusanSettings]>([])
        let store = settingsStore {
            $0.kakusan.saveSettings = { value in saved.withValue { $0.append(value) } }
        }
        await loaded(store)
        var expected = KakusanMediaTuning()
        expected.queueAgeMinimumMs = 500
        expected.queueAgeMaximumMs = 500
        await store.send(.editTuning(.queueAgeMinimumMs, "500")) {
            $0.tuningDraft[.queueAgeMinimumMs] = "500"
        }
        await store.send(.saveTuning) {
            $0.tuning = .saving(id(3))
        }
        await store.receive(.tuningSaved(id(3), expected)) {
            $0.configuration.tuning = expected
            $0.tuningDraft = KakusanTuningDraft(expected)
            $0.tuning = .ready
        }
        #expect(saved.value == [KakusanSettings(tuning: expected)])
    }

    @MainActor @Test func restoringDefaultTuningKeepsTheStunServers() async {
        let saved = LockIsolated<[KakusanSettings]>([])
        let store = settingsStore {
            $0.kakusan.loadSettings = { customSettings }
            $0.kakusan.saveSettings = { value in saved.withValue { $0.append(value) } }
        }
        await loaded(store, customSettings)
        #expect(!store.state.tuningDefaultsBlocked)
        await store.send(.editTuning(.queuePackets, "1")) {
            $0.tuningDraft[.queuePackets] = "1"
            $0.tuning = .invalid
        }
        await store.send(.restoreDefaultTuning) {
            $0.tuning = .saving(id(3))
        }
        await store.receive(.tuningSaved(id(3), KakusanMediaTuning())) {
            $0.configuration.tuning = KakusanMediaTuning()
            $0.tuningDraft = KakusanTuningDraft()
            $0.tuning = .ready
        }
        #expect(saved.value == [KakusanSettings(stunServers: customServers)])
        #expect(store.state.tuningDefaultsBlocked)
        await store.send(.restoreDefaultStun) {
            $0.stun = .saving(id(4))
        }
        await store.receive(.stunSaved(id(4), KakusanSettings())) {
            $0.configuration.stunServers = []
            $0.stunDraft = ""
            $0.stun = .ready
        }
        #expect(saved.value.last == KakusanSettings())
    }

    @MainActor @Test func tuningFailuresAreReported() async {
        let store = settingsStore {
            $0.kakusan.saveSettings = { _ in throw KakusanError.internal }
        }
        await loaded(store)
        await store.send(.editTuning(.dropSecondsToEnd, "20")) {
            $0.tuningDraft[.dropSecondsToEnd] = "20"
        }
        await store.send(.saveTuning) {
            $0.tuning = .saving(id(3))
        }
        await store.receive(.tuningFailed(id(3))) {
            $0.tuning = .failed
        }
        #expect(store.state.configuration.tuning == KakusanMediaTuning())
        #expect(store.state.tuningDraft[.dropSecondsToEnd] == "20")
        #expect(!store.state.tuningSaveBlocked)
    }

    @MainActor @Test func settingsLoadFailureFailsStunAndTuning() async {
        let store = settingsStore {
            $0.kakusan.loadSettings = { throw KakusanError.internal }
        }
        await store.send(.load) {
            $0.identity = .loading(id(0))
            $0.stun = .loading(id(1))
            $0.tuning = .loading(id(1))
            $0.peers = .loading(id(2))
        }
        await store.receive(.identityLoaded(id(0), identity)) {
            $0.identity = .ready(identity)
        }
        await store.receive(.settingsFailed(id(1))) {
            $0.stun = .failed
            $0.tuning = .failed
        }
        await store.receive(.peersLoaded(id(2), [alex, sam])) {
            $0.peers = .ready([alex, sam])
        }
        await store.send(.tuningSaved(id(1), customTuning))
    }
#endif
