import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The Network settings' NAT type group: a Check button and what the latest check found, as type 1, 2 or 3.
public struct NatTypeSettingsView: View {
    /// The check.
    let store: StoreOf<NatTypeFeature>

    /// Creates the group.
    ///
    /// - Parameter store: The check.
    public init(store: StoreOf<NatTypeFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.settingsNetworkNatHeading).font(.headline)
            HStack(spacing: 12) {
                FocusButton {
                    store.send(.checkTapped)
                } label: {
                    Label(
                        store.isChecking
                            ? .settingsNetworkNatChecking
                            : .settingsNetworkNatCheck,
                        systemImage: "network"
                    )
                }
                .glassControlStyle()
                .disabled(store.isChecking)
                .accessibilityIdentifier("nat-type-check")
                if store.isChecking {
                    ProgressView().controlSize(.small)
                }
                if case .found(let type) = store.check {
                    Text(.settingsNetworkNatFoundType(type: String(type.rawValue)))
                        .font(.headline)
                        .accessibilityLabel(.settingsNetworkNatFoundTypeLabel(type: String(type.rawValue)))
                }
            }
            Text(Self.detail(store.check))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear {
            store.send(.stopped)
        }
    }

    /// The line under the button about the latest check.
    ///
    /// - Parameter check: Where the check stands.
    /// - Returns: The line.
    static func detail(_ check: NatTypeFeature.Check) -> LocalizedStringResource {
        switch check {
        case .idle, .checking:
            .settingsNetworkNatIdleDetail
        case .found(.type1):
            .settingsNetworkNatPublicDetail
        case .found(.type2):
            KakusanBuild.included
                ? .settingsNetworkNatMappedKakusanDetail
                : .settingsNetworkNatMappedDetail
        case .found(.type3):
            .settingsNetworkNatStrictDetail
        case .failed(.unanswered):
            .settingsNetworkNatUnansweredDetail
        case .failed(.incomplete):
            .settingsNetworkNatIncompleteDetail
        case .failed(.unresolved):
            .settingsNetworkNatUnresolvedDetail
        case .failed(.network), .failed(.cancelled):
            .settingsNetworkNatFailedDetail
        }
    }
}
