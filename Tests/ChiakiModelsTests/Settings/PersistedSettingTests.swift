import ChiakiModels
import Foundation
import Testing

@Suite struct PersistedSettingTests {
    struct Volume: PersistedSettingValue {
        enum Failure: Error {
            case outOfRange
        }

        static let settingKey = SettingKey(name: "test.volume", defaultValue: Volume(level: 5))

        var level: Int

        func normalized() -> Volume {
            Volume(level: max(level, 0))
        }

        func validated() throws(Failure) -> Volume {
            guard level <= 10 else {
                throw .outOfRange
            }
            return self
        }
    }

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    @Test func editsAreRefusedUntilTheStoredValueHasLoaded() {
        var setting = PersistedSetting<Volume>.unloaded
        #expect(setting.edit(Volume(level: 7)) == .refused)
        let began = setting.beginLoad(operation(0))
        #expect(began)
        #expect(setting.edit(Volume(level: 7)) == .refused)
        setting.finishLoad(operation(0), .failure(.unavailable))
        #expect(setting.edit(Volume(level: 7)) == .refused)
        #expect(setting == .loadFailed(.unavailable))
    }

    @Test func aStaleLoadCompletionIsIgnored() {
        var setting = PersistedSetting<Volume>.unloaded
        let began = setting.beginLoad(operation(0))
        #expect(began)
        let stale = setting.finishLoad(operation(1), .success(Volume(level: 2)))
        #expect(!stale)
        #expect(setting == .loading(operation(0)))
        let current = setting.finishLoad(operation(0), .success(Volume(level: 2)))
        #expect(current)
        #expect(setting == .ready(saved: Volume(level: 2)))
    }

    @Test func aValidEditIsSavedAndANewerDraftFollowsTheRunningSave() {
        var setting = PersistedSetting<Volume>.ready(saved: Volume(level: 2))
        #expect(setting.edit(Volume(level: 3)) == .save(Volume(level: 3)))
        setting.beginSave(operation(0), value: Volume(level: 3))
        #expect(setting.edit(Volume(level: 4)) == .queued)
        #expect(setting == .saving(operation(0), saved: Volume(level: 2), draft: Volume(level: 4)))
        #expect(setting.finishSave(operation(1), .success(Volume(level: 3))) == nil)
        #expect(setting.finishSave(operation(0), .success(Volume(level: 3))) == Volume(level: 4))
        setting.beginSave(operation(2), value: Volume(level: 4))
        #expect(setting.finishSave(operation(2), .success(Volume(level: 4))) == nil)
        #expect(setting == .ready(saved: Volume(level: 4)))
    }

    @Test func anInvalidDraftIsHeldUntilAValidEditCommitsIt() {
        var setting = PersistedSetting<Volume>.ready(saved: Volume(level: 2))
        #expect(setting.edit(Volume(level: 11)) == .invalid)
        #expect(setting == .saveFailed(saved: Volume(level: 2), draft: Volume(level: 11), failure: .invalid))
        #expect(setting.value == Volume(level: 11))
        #expect(setting.edit(Volume(level: -3)) == .save(Volume(level: 0)))
    }

    @Test func aFailedWriteKeepsTheDraftAndTheSavedValue() {
        var setting = PersistedSetting<Volume>.ready(saved: Volume(level: 2))
        setting.beginSave(operation(0), value: Volume(level: 6))
        #expect(setting.finishSave(operation(0), .failure(.unavailable)) == nil)
        #expect(setting == .saveFailed(
            saved: Volume(level: 2),
            draft: Volume(level: 6),
            failure: .unavailable
        ))
        let reloaded = setting.beginLoad(operation(1))
        #expect(!reloaded)
        #expect(setting.edit(Volume(level: 2)) == .unchanged)
        #expect(setting == .ready(saved: Volume(level: 2)))
    }
}
