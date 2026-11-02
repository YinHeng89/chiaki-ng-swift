import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Cloud stream picture settings and the bandwidth the last PS5 cloud stream measured.
@Reducer
public struct CloudPictureSettingsFeature {
    /// Where the saved bandwidth is.
    public enum SavedBandwidth: Equatable, Sendable {
        /// Not read yet.
        case unread

        /// Being read by the operation with this id.
        case reading(OperationID)

        /// Read; `nil` when nothing was measured or it could not be read.
        case read(CloudSavedBandwidth?)
    }

    /// The cloud picture state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The saved cloud picture settings.
        public var picture = PersistedSettingFeature<CloudPictureSettings>.State()

        /// The bandwidth measured for PS5 cloud streams.
        public internal(set) var savedBandwidth = SavedBandwidth.unread

        /// Creates the state with nothing loaded.
        public init() {
        }

        /// The measured bandwidth, once read.
        public var measuredBandwidth: CloudSavedBandwidth? {
            if case let .read(value) = savedBandwidth {
                return value
            }
            return nil
        }
    }

    /// Everything the cloud picture settings react to.
    public enum Action: Equatable, Sendable {
        /// The saved settings.
        case picture(PersistedSettingFeature<CloudPictureSettings>.Action)

        /// The settings appeared; loads them and reads the saved bandwidth.
        case appeared

        /// The saved bandwidth was read.
        case savedBandwidthRead(OperationID, CloudSavedBandwidth?)
    }

    private enum CancelID {
        case savedBandwidth
    }

    @Dependency(\.settings) private var settingsStore
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.picture, action: \.picture) {
            PersistedSettingFeature<CloudPictureSettings>()
        }
        Reduce { state, action in
            switch action {
            case .picture:
                return .none
            case .appeared:
                let id = OperationID(uuid: uuid())
                state.savedBandwidth = .reading(id)
                return .merge(
                    .send(.picture(.appeared)),
                    .run { [settingsStore] send in
                        let datacenters = try? await settingsStore.load(CloudDatacenterSettings.self)
                        await send(.savedBandwidthRead(id, datacenters?.latestBandwidth(for: .psCloud)))
                    }
                    .cancellable(id: CancelID.savedBandwidth, cancelInFlight: true)
                )
            case let .savedBandwidthRead(id, value):
                guard state.savedBandwidth == .reading(id) else {
                    return .none
                }
                state.savedBandwidth = .read(value)
                return .none
            }
        }
    }
}
