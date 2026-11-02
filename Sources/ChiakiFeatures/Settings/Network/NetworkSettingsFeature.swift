import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// Console discovery settings: the unicast sweep and the subnets it searches.
///
/// The subnets are typed as text, one per line. Every change is parsed and handed to the saved
/// `DiscoverySettings`, which the core checks as it saves. A refused save keeps the text exactly as typed and
/// reports ``State/subnetsRejected`` until a later edit saves.
@Reducer
public struct NetworkSettingsFeature {
    /// The discovery settings state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The saved discovery settings.
        public var discovery = PersistedSettingFeature<DiscoverySettings>.State()

        /// The subnets as typed.
        public var subnets = ""

        /// Creates the state with nothing loaded.
        public init() {
        }

        /// Whether the core refused the typed subnets, so the field shows why and keeps focus.
        public var subnetsRejected: Bool {
            if case .saveFailed(_, _, .invalid) = discovery.setting {
                return true
            }
            return false
        }
    }

    /// Everything the discovery settings react to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to the subnets text.
        case binding(BindingAction<State>)

        /// The saved settings.
        case discovery(PersistedSettingFeature<DiscoverySettings>.Action)

        /// The settings appeared.
        case appeared
    }

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Scope(state: \.discovery, action: \.discovery) {
            PersistedSettingFeature<DiscoverySettings>()
        }
        Reduce { state, action in
            switch action {
            case .binding(\.subnets):
                guard state.discovery.isEditable else {
                    state.subnets = Self.text(of: state.discovery.draft)
                    return .none
                }
                var value = state.discovery.draft
                value.subnets = Self.subnets(in: state.subnets)
                return .send(.discovery(.edit(value)))
            case let .discovery(.delegate(.loaded(value))):
                state.subnets = Self.text(of: value)
                return .none
            case .binding, .discovery:
                return .none
            case .appeared:
                return .send(.discovery(.appeared))
            }
        }
    }

    private static func subnets(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    }

    private static func text(of settings: DiscoverySettings) -> String {
        settings.subnets.joined(separator: "\n")
    }
}

/// Console discovery settings.
public struct NetworkSettingsView: View {
    /// The network settings feature holding the discovery settings and the subnet text.
    @Bindable public var store: StoreOf<NetworkSettingsFeature>
    /// Which discovery control has controller focus.
    @MenuFocusState.Binding var focus: NetworkSettingsFocus?

    /// Creates a network settings view.
    ///
    /// - Parameters:
    ///   - store: The network settings feature holding the discovery settings and the subnet text.
    ///   - focus: Which discovery control has controller focus.
    public init(store: StoreOf<NetworkSettingsFeature>,
                focus: MenuFocusState<NetworkSettingsFocus?>.Binding) {
        self.store = store
        _focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Console discovery").font(.headline)
            Text(
                "Local networks are discovered automatically. Add other subnets to search them directly."
            )
            .font(.caption).foregroundStyle(.secondary)
            NetworkSweepToggle(store: store.scope(state: \.discovery, action: \.discovery), focus: $focus)
            TextField("192.168.2.0/24", text: $store.subnets, axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.plain)
                .menuFocusBinding($focus, equals: .subnets)
                .controllerKeyboard(
                    title: "Discovery subnets",
                    text: $store.subnets,
                    isFocused: focus == .subnets,
                    allowsNewline: true
                )
                .padding(12).glassPanel(.small)
                .overlay {
                    if store.subnetsRejected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.red, lineWidth: 1.5)
                    }
                }
                .accessibilityLabel("Discovery subnets")
            if store.subnetsRejected {
                Label(
                    "Enter IPv4 subnets from /24 to /32, up to 1,024 addresses, for example 192.168.2.0/24.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
            Text(
                "One subnet per line, /24–/32. Up to 1,024 addresses. Local subnets use broadcast."
            )
            .font(.caption).foregroundStyle(.secondary)
            SettingsPersistenceBanner(
                store.discovery.setting,
                subject: "network settings",
                reportsInvalid: false
            ) {
                store.send(.discovery(.retry))
            }
        }
        .disabled(loadFailed)
        .onAppear {
            store.send(.appeared)
        }
    }

    private var loadFailed: Bool {
        if case .loadFailed = store.discovery.setting {
            return true
        }
        return false
    }
}

/// Turns the unicast sweep of the saved discovery settings on or off.
public struct NetworkSweepToggle: View {
    /// The persisted discovery settings whose unicast sweep flag the toggle edits.
    @Bindable public var store: StoreOf<PersistedSettingFeature<DiscoverySettings>>
    /// Which discovery control has controller focus, set to the sweep toggle when it is focused.
    @MenuFocusState.Binding var focus: NetworkSettingsFocus?

    public var body: some View {
        Toggle("Unicast sweep", isOn: $store.draft.unicastEnabled)
            .menuFocusBinding($focus, equals: .sweep)
            .accessibilityIdentifier("network-unicast-sweep")
    }
}
