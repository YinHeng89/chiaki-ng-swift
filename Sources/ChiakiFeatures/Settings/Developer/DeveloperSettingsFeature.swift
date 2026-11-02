import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The Developer tab beyond logging: Takion versions, the log's health and the error report.
@Reducer
public struct DeveloperSettingsFeature {
    /// Whether the log file can be written.
    public enum LogHealth: Equatable, Sendable {
        /// Not checked yet.
        case unchecked

        /// Being checked by the operation with this id.
        case checking(OperationID)

        /// The last check found the log and capture files writable.
        case healthy

        /// The last check found a file that could not be written.
        case unwritable
    }

    /// Where building the error report is.
    public enum ReportExport: Equatable, Sendable {
        /// Nothing is being built.
        case idle

        /// The report is being built by the operation with this id.
        case building(OperationID)

        /// The last report could not be built.
        case failed
    }

    /// The tab's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The saved Takion version settings.
        public var takion = PersistedSettingFeature<DeveloperSettings>.State()

        /// The Takion versions this build negotiates when a target is automatic.
        public internal(set) var buildTakionVersions: [TakionTarget: UInt32] = [:]

        /// Whether the log can be written.
        public internal(set) var logHealth = LogHealth.unchecked

        /// Where building the error report is.
        public internal(set) var report = ReportExport.idle

        /// Creates the tab with nothing loaded.
        public init() {
        }

        /// The versions a target can be pinned to, automatic first.
        ///
        /// - Parameter target: The connection kind.
        /// - Returns: The versions to offer.
        public func choices(for target: TakionTarget) -> [UInt32] {
            [DeveloperSettings.automaticTakionVersion] + DeveloperSettings.takionVersions(for: target)
        }

        /// The version this build negotiates for a target left automatic.
        ///
        /// - Parameter target: The connection kind.
        /// - Returns: The build's version.
        public func buildTakionVersion(for target: TakionTarget) -> UInt32 {
            buildTakionVersions[target] ?? DeveloperSettings.automaticTakionVersion
        }
    }

    /// Everything the Developer tab reacts to.
    public enum Action: Equatable, Sendable {
        /// The saved Takion version settings.
        case takion(PersistedSettingFeature<DeveloperSettings>.Action)

        /// The tab appeared.
        case appeared

        /// The log health check finished.
        case logHealthChecked(OperationID, healthy: Bool)

        /// Build the error report.
        case exportReport

        /// Building the error report finished.
        case reportBuilt(OperationID, String?)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the Developer tab reports to its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// An error report was built and should be shown.
            case reportReady(String)
        }
    }

    @Dependency(\.logSettings) private var logging
    @Dependency(\.settings) private var settings
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.takion, action: \.takion) {
            PersistedSettingFeature<DeveloperSettings>()
        }
        Reduce { state, action in
            switch action {
            case .takion, .delegate:
                return .none
            case .appeared:
                let id = OperationID(uuid: uuid())
                state.logHealth = .checking(id)
                state.buildTakionVersions = Dictionary(
                    uniqueKeysWithValues: TakionTarget.allCases.map { target in
                        (target, settings.buildTakionVersion(target))
                    }
                )
                return .merge(
                    .send(.takion(.appeared)),
                    .run { [logging] send in
                        await send(.logHealthChecked(id, healthy: logging.health()))
                    }
                )
            case let .logHealthChecked(id, healthy):
                guard state.logHealth == .checking(id) else {
                    return .none
                }
                state.logHealth = healthy
                    ? .healthy
                    : .unwritable
                return .none
            case .exportReport:
                if case .building = state.report {
                    return .none
                }
                let id = OperationID(uuid: uuid())
                state.report = .building(id)
                return .run { [logging] send in
                    let text = try? await logging.exportReport()
                    await send(.reportBuilt(id, text))
                }
            case let .reportBuilt(id, text):
                guard state.report == .building(id) else {
                    return .none
                }
                guard let text else {
                    state.report = .failed
                    return .none
                }
                state.report = .idle
                return .send(.delegate(.reportReady(text)))
            }
        }
    }
}
