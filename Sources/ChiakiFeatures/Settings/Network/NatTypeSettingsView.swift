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
            Text("NAT type").font(.headline)
            HStack(spacing: 12) {
                FocusButton {
                    store.send(.checkTapped)
                } label: {
                    Label(
                        store.isChecking
                            ? "Checking"
                            : "Check NAT type",
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
                    Text("Type \(type.rawValue)")
                        .font(.headline)
                        .accessibilityLabel("NAT type \(type.rawValue)")
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
    static func detail(_ check: NatTypeFeature.Check) -> String {
        switch check {
        case .idle, .checking:
            "Finds how reachable this device is from the internet, as type 1, 2 or 3."
        case .found(.type1):
            "This device has a public address. Internet connections to and from it should work."
        case .found(.type2):
            "This device is behind a router that keeps one public address and port for it. "
                + (KakusanBuild.included
                    ? "Remote Play and Kakusan over the internet usually connect."
                    : "Remote Play over the internet usually connects.")
        case .found(.type3):
            "This device is behind a strict router. Internet connections may fail; turn on Always guess ports, "
                + "or enable UPnP or port forwarding on the router."
        case .failed(.unanswered):
            "No STUN server answered. Your network may block UDP."
        case .failed(.incomplete):
            "Only one server answered, which isn't enough to tell type 2 from type 3. Try again."
        case .failed(.unresolved):
            "The servers couldn't be found. Check your internet connection."
        case .failed(.network), .failed(.cancelled):
            "The check couldn't run. Try again."
        }
    }
}
