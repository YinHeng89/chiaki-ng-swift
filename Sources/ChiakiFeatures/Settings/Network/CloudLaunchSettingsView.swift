import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus
import SwiftUI

/// Loads and saves whether the user picks a cloud datacenter before each stream, tying every completion to
/// the request that started it.
@Reducer public struct CloudLaunchSettingsReducer {
    /// The load and save workflow of the setting.
    public enum Phase: Equatable, Sendable {
        /// Not loaded yet, loading under an identifier, ready, saving a pending value under an identifier, or
        /// failed with a message.
        case idle, loading(UUID), ready, saving(UUID, Bool), failed(LocalizedStringResource)
    }

    /// The persisted choice and where its load or save stands.
    @ObservableState public struct State: Equatable {
        /// Where the setting is in its load and save workflow.
        public var phase: Phase = .idle
        /// Whether a datacenter is chosen before each cloud stream, as last loaded or saved.
        public var selectsAtLaunch = true
        /// Creates state that has not loaded the setting yet.
        public init() {
        }

        /// Whether a load or save is in flight.
        public var busy: Bool {
            switch phase {
            case .loading, .saving:
                true
            default:
                false
            }
        }

        /// The value the toggle shows: the pending value while saving, otherwise the saved value.
        public var displayedValue: Bool {
            if case .saving(_, let pending) = phase {
                return pending
            }
            return selectsAtLaunch
        }
    }

    /// Events that load and save the datacenter choice.
    public enum Action: Equatable, Sendable {
        /// Loads the saved setting unless a request is already in flight.
        case load
        /// The load with this identifier returned these settings.
        case loaded(UUID, CloudDatacenterSettings)
        /// The user turned choosing a datacenter at launch on or off.
        case setSelectAtLaunch(Bool)
        /// The save with this identifier returned the stored settings.
        case saved(UUID, CloudDatacenterSettings)
        /// The load or save with this identifier failed.
        case failed(UUID)
    }

    /// The toggle's label.
    public static let title: LocalizedStringResource = .settingsNetworkCloudLaunchToggle
    /// The caption explaining what choosing a datacenter at launch does.
    public static let detail: LocalizedStringResource = .settingsNetworkCloudLaunchDetail

    /// Reads and writes the cloud datacenter settings.
    @Dependency(\.cloud) var client
    /// Generates the identifiers that tie each completion to its request.
    @Dependency(\.uuid) var uuid
    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.busy else {
                    return .none
                }
                let id = uuid()
                state.phase = .loading(id)
                return .run { [client] send in
                    do {
                        await send(.loaded(id, try await client.loadDatacenters()))
                    } catch {
                        await send(.failed(id))
                    }
                }
            case let .loaded(id, value):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.selectsAtLaunch = value.selectsAtLaunch
                state.phase = .ready
                return .none
            case .setSelectAtLaunch(let enabled):
                guard !state.busy, enabled != state.selectsAtLaunch else {
                    return .none
                }
                let id = uuid()
                state.phase = .saving(id, enabled)
                return .run { [client] send in
                    do {
                        await send(.saved(id, try await client.setSelectAtLaunch(enabled)))
                    } catch {
                        await send(.failed(id))
                    }
                }
            case let .saved(id, value):
                guard case .saving(id, _) = state.phase else {
                    return .none
                }
                state.selectsAtLaunch = value.selectsAtLaunch
                state.phase = .ready
                return .none
            case .failed(let id):
                switch state.phase {
                case .loading(id), .saving(id, _):
                    state.phase = .failed(.settingsNetworkCloudLaunchFailed)
                default:
                    break
                }
                return .none
            }
        }
    }
}

/// Whether a datacenter is chosen before each cloud stream.
public struct CloudLaunchSettingsView: View {
    /// The reducer that loads and saves the datacenter choice.
    public let store: StoreOf<CloudLaunchSettingsReducer>

    /// Creates a cloud launch settings view.
    ///
    /// - Parameter store: The reducer that loads and saves the datacenter choice.
    public init(store: StoreOf<CloudLaunchSettingsReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.settingsNetworkCloudDatacenterHeading).font(.headline)
            Toggle(
                CloudLaunchSettingsReducer.title,
                isOn: Binding(
                    get: {
                        store.displayedValue
                    },
                    set: {
                        store.send(.setSelectAtLaunch($0))
                    }
                )
            )
            .disabled(store.busy || store.phase == .idle)
            Text(CloudLaunchSettingsReducer.detail)
                .font(.caption).foregroundStyle(.secondary)
            if case .failed(let message) = store.phase {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            store.send(.load)
        }
    }
}
