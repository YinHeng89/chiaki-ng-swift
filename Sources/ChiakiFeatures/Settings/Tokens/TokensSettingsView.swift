import ChiakiModels
import SwiftUI
import PlatformUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// Lists each PlayStation account's credentials with their state, and reveals a held credential's secret for
/// a limited time after the device owner authenticates.
public struct TokensSettingsView: View {
    /// The tokens reducer that owns the accounts and the reveal workflow.
    public let store: StoreOf<TokensReducer>

    /// Creates a tokens settings view.
    ///
    /// - Parameter store: The tokens reducer that owns the accounts and the reveal workflow.
    public init(store: StoreOf<TokensReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if store.phase == .ready, store.accounts.isEmpty {
                Text(.settingsTokensNoAccounts).foregroundStyle(.secondary)
            }
            ForEach(store.accounts) { account in
                SettingsCard(verbatim: account.name) {
                    ForEach(Array(account.credentials.enumerated()),
                            id: \.element.kind) { index, credential in
                        if index > 0 {
                            Divider()
                        }
                        row(HeldCredentialPresentation(credential), of: account)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.resignedActiveNotification)) { _ in
            store.send(.resignedActive)
        }
        .onAppear {
            store.send(.load)
        }
        .onDisappear {
            store.send(.lock)
        }
    }

    private static var resignedActiveNotification: Notification.Name {
        #if os(macOS)
            NSApplication.didResignActiveNotification
        #else
            UIApplication.willResignActiveNotification
        #endif
    }

    private var controls: some View {
        HStack(spacing: 12) {
            FocusButton(.commonRefresh) {
                store.send(.load)
            }
            .glassControlStyle()
            .disabled(store.busy)
            .accessibilityIdentifier("tokens-refresh")
            if store.busy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func row(_ credential: HeldCredentialPresentation, of account: TokenAccount) -> some View {
        let target = TokensReducer.Target(account: account.id, kind: credential.id)
        let name = "\(account.id.uuidString)-\(credential.id)"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(credential.title).font(.callout.weight(.medium))
                Text(credential.status).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if case .authenticating(target, _) = store.reveal {
                    ProgressView().controlSize(.small)
                }
                FocusButton(shows(target)
                    ? .commonHide
                    : .settingsTokensReveal) {
                        if shows(target) {
                            store.send(.hide)
                        } else {
                            store.send(.reveal(target))
                        }
                    }
                    .glassControlStyle()
                    .disabled(!credential.held)
                    .accessibilityIdentifier("tokens-reveal-\(name)")
            }
            .frame(minHeight: 30)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(credential.facts) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fact.label).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(fact.value).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if case .shown(target, let id) = store.reveal,
               let text = store.secrets?.text(for: OperationID(uuid: id)) {
                revealed(text, name: name)
            }
            if case .refused(target, let message) = store.reveal {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func revealed(_ text: String, name: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text).font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .accessibilityIdentifier("tokens-secret-\(name)")
            FocusButton(.settingsTokensCopy) {
                copy(text)
            }
            .glassControlStyle()
            .accessibilityIdentifier("tokens-copy-\(name)")
        }
    }

    private func shows(_ target: TokensReducer.Target) -> Bool {
        if case .shown(target, _) = store.reveal {
            return true
        }
        return false
    }

    private func copy(_ text: String) {
        PlatformPasteboard.copyConcealed(text)
    }
}
