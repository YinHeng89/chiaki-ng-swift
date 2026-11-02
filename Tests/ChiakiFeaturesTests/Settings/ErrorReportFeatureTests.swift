import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

@MainActor
@Suite struct ErrorReportFeatureTests {
    let id = UUID()
    let destination = URL(fileURLWithPath: "/tmp/report.txt")

    @Test func aFailedSaveIsShownInsteadOfSwallowed() async {
        let store = TestStore(initialState: ErrorReportFeature.State(text: "report")) {
            ErrorReportFeature()
        } withDependencies: { [id, destination] in
            $0.uuid = .constant(id)
            $0.platform.chooseReportDestination = { _ in
                destination
            }
            $0.platform.writeReport = { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        await store.send(.save) {
            $0.saving = .choosingDestination
        }
        #if os(macOS)
            await store.receive(.destinationChosen(destination)) {
                $0.saving = .writing(OperationID(uuid: id))
            }
            await store.receive(.written(OperationID(uuid: id), succeeded: false)) {
                $0.saving = .failed
            }
        #endif
    }

    @Test func aSavedReportWritesItsTextWhereTheUserChose() async {
        let written = LockIsolated<[String]>([])
        var initial = ErrorReportFeature.State(text: "report")
        initial.saving = .choosingDestination
        let store = TestStore(initialState: initial) {
            ErrorReportFeature()
        } withDependencies: { [id] in
            $0.uuid = .constant(id)
            $0.platform.writeReport = { text, url in
                written.withValue {
                    $0.append("\(text) \(url.path)")
                }
            }
        }
        await store.send(.destinationChosen(destination)) {
            $0.saving = .writing(OperationID(uuid: id))
        }
        await store.receive(.written(OperationID(uuid: id), succeeded: true)) {
            $0.saving = .saved
        }
        #expect(written.value == ["report /tmp/report.txt"])
    }

    @Test func cancellingTheDestinationLeavesNothingSaved() async {
        var initial = ErrorReportFeature.State(text: "report")
        initial.saving = .choosingDestination
        let store = TestStore(initialState: initial) {
            ErrorReportFeature()
        }
        await store.send(.destinationChosen(nil)) {
            $0.saving = .idle
        }
        await store.send(.written(OperationID(), succeeded: true))
    }
}
