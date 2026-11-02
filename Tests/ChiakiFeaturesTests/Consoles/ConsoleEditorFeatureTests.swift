import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct ConsoleEditorFeatureTests {
    let console = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    var draft: ConsoleDraft {
        ConsoleDraft(
            id: console, name: "Living room", address: "192.0.2.5", generation: "PS5",
            remoteAvailable: false, hardwareID: "aabbccddeeff"
        )
    }

    func store(
        _ state: ConsoleEditorFeature.State = ConsoleEditorFeature.State(),
        options: Result<ConsoleLaunchOptions, ConsoleEditFailure> = .success(ConsoleLaunchOptions()),
        save: @escaping @Sendable (ConsoleDraft) async -> ConsoleEditFailure? = { _ in nil },
        delete: @escaping @Sendable (UUID) async -> ConsoleEditFailure? = { _ in nil }
    ) -> TestStoreOf<ConsoleEditorFeature> {
        TestStore(initialState: state) {
            ConsoleEditorFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.consoles.launchOptions = { _ in
                options
            }
            $0.consoles.saveDraft = save
            $0.consoles.deleteConsole = delete
        }
    }

    @Test func theEditorLoadsTheOptionsAndSavesTheDraftWithThem() async {
        let saved = LockIsolated<ConsoleDraft?>(nil)
        let store = store(options: .success(ConsoleLaunchOptions(
            connectAtLaunch: true,
            loginPINSaved: true
        ))) {
            saved.setValue($0)
            return nil
        }
        let draft = draft
        await store.send(.edit(draft)) {
            $0.flow = .loading(operation(0), draft)
        }
        var loaded = draft
        loaded.connectAtLaunch = true
        loaded.loginPIN = .saved
        await store.receive(.optionsLoaded(operation(0), .success(ConsoleLaunchOptions(
            connectAtLaunch: true, loginPINSaved: true
        )))) {
            $0.flow = .editing(loaded)
        }
        loaded.name = "Den"
        await store.send(.view(.setName("Den"))) {
            $0.flow = .editing(loaded)
        }
        loaded.loginPIN = .forgotten
        await store.send(.view(.forgetLoginPIN)) {
            $0.flow = .editing(loaded)
        }
        await store.send(.view(.confirm)) {
            $0.flow = .saving(operation(1), loaded)
        }
        await store.receive(.finished(operation(1), nil)) {
            $0.flow = .closed
        }
        await store.receive(.delegate(.changed))
        await store.receive(.delegate(.closed))
        #expect(saved.value == loaded)
    }

    @Test func deletingFromTheEditorKeepsTheDraftWhenWithdrawn() async {
        var edited = draft
        edited.name = "Unsaved name"
        var initial = ConsoleEditorFeature.State()
        initial.flow = .editing(edited)
        let store = store(initial)
        await store.send(.view(.delete)) {
            $0.flow = .confirmingDeletion(edited.id, returning: edited)
        }
        await store.send(.view(.cancel)) {
            $0.flow = .editing(edited)
        }
    }

    @Test func aFailedDeletionFromTheEditorReturnsToTheDraft() async {
        var edited = draft
        edited.address = "192.0.2.99"
        var initial = ConsoleEditorFeature.State()
        initial.flow = .editing(edited)
        let store = store(initial, delete: { _ in .deleteFailed })
        await store.send(.view(.delete)) {
            $0.flow = .confirmingDeletion(edited.id, returning: edited)
        }
        await store.send(.view(.confirm)) {
            $0.flow = .deleting(operation(0), edited.id, returning: edited)
        }
        await store.receive(.finished(operation(0), .deleteFailed)) {
            $0.flow = .failed(.deleteFailed, returning: edited)
        }
        await store.send(.view(.cancel)) {
            $0.flow = .editing(edited)
        }
    }

    @Test func aFailedSaveReturnsToTheDraftInsteadOfDroppingIt() async {
        var initial = ConsoleEditorFeature.State()
        initial.flow = .editing(draft)
        let draft = draft
        let store = store(initial, save: { _ in .saveFailed })
        await store.send(.view(.confirm)) {
            $0.flow = .saving(operation(0), draft)
        }
        await store.receive(.finished(operation(0), .saveFailed)) {
            $0.flow = .failed(.saveFailed, returning: draft)
        }
        await store.send(.view(.cancel)) {
            $0.flow = .editing(draft)
        }
    }

    @Test func aDeletionFromTheLibraryNeedsConfirmationAndReportsTheChange() async {
        let console = console
        let clock = TestClock()
        let store = store(delete: { requested in
            #expect(requested == console)
            try? await clock.sleep(for: .seconds(1))
            return nil
        })
        await store.send(.requestDeletion(console)) {
            $0.flow = .confirmingDeletion(console, returning: nil)
        }
        await store.send(.view(.confirm)) {
            $0.flow = .deleting(operation(0), console, returning: nil)
        }
        await store.send(.finished(operation(9), .deleteFailed))
        await clock.advance(by: .seconds(1))
        await store.receive(.finished(operation(0), nil)) {
            $0.flow = .closed
        }
        await store.receive(.delegate(.changed))
        await store.receive(.delegate(.closed))
    }

    @Test func anInvalidDraftIsNotSaved() async {
        var invalid = draft
        invalid.address = "two words"
        var initial = ConsoleEditorFeature.State()
        initial.flow = .editing(invalid)
        let store = store(initial)
        await store.send(.view(.confirm))
    }

    @Test func closingWhileLoadingIgnoresTheLateOptions() async {
        let draft = draft
        let gate = AsyncStream.makeStream(of: Void.self)
        let store = TestStore(initialState: ConsoleEditorFeature.State()) {
            ConsoleEditorFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.consoles.launchOptions = { _ in
                for await _ in gate.stream {
                    break
                }
                return .success(ConsoleLaunchOptions(connectAtLaunch: true))
            }
        }
        await store.send(.edit(draft)) {
            $0.flow = .loading(operation(0), draft)
        }
        await store.send(.view(.cancel)) {
            $0.flow = .closed
        }
        await store.receive(.delegate(.closed))
        gate.continuation.yield()
        await store.receive(.optionsLoaded(
            operation(0),
            .success(ConsoleLaunchOptions(connectAtLaunch: true))
        ))
    }
}
