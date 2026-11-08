import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The touch Tokens page: one group per signed-in PlayStation account listing its credentials with their state,
/// where a held credential's secret is revealed for a limited time after the device owner authenticates.
struct MobileTokensSettingsPage: View {
    /// The settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        let accounts = store.accounts
        let half = (accounts.count + 1) / 2
        MobileSettingsForm {
            controls
            ForEach(accounts.prefix(half)) { account in
                group(account)
            }
        } trailing: {
            ForEach(accounts.dropFirst(half)) { account in
                group(account)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.resignedActiveNotification)) { _ in
            settings.send(.tokens(.resignedActive))
        }
        .onAppear {
            settings.send(.tokens(.load))
        }
        .onDisappear {
            settings.send(.tokens(.lock))
        }
    }

    private static var resignedActiveNotification: Notification.Name {
        #if os(macOS)
            NSApplication.didResignActiveNotification
        #else
            UIApplication.willResignActiveNotification
        #endif
    }

    private var store: StoreOf<TokensReducer> {
        settings.scope(state: \.tokens, action: \.tokens)
    }

    private var controls: some View {
        MobileSettingsGroup {
            MobileButtonRow(.commonRefresh) {
                store.send(.load)
            }
            .disabled(store.busy)
            .overlay(alignment: .trailing) {
                if store.busy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            .accessibilityIdentifier("tokens-refresh")
            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            }
            if store.phase == .ready, store.accounts.isEmpty {
                Text(.mobileTokensNoAccounts)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            }
        }
    }

    private func group(_ account: TokenAccount) -> some View {
        MobileSettingsGroup(verbatim: account.name) {
            ForEach(account.credentials, id: \.kind) { credential in
                row(HeldCredentialPresentation(credential), of: account)
            }
        }
    }

    private func row(_ credential: HeldCredentialPresentation, of account: TokenAccount) -> some View {
        let target = TokensReducer.Target(account: account.id, kind: credential.id)
        let name = "\(account.id.uuidString)-\(credential.id)"
        let showing = shows(target)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MobileRowTitle(title: credential.title, detail: credential.status)
                Spacer(minLength: 8)
                if case .authenticating(target, _) = store.reveal {
                    ProgressView()
                        .controlSize(.small)
                }
                FocusButton(
                    showing
                        ? .commonHide
                        : .mobileTokensReveal
                ) {
                    if showing {
                        store.send(.hide)
                    } else {
                        store.send(.reveal(target))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!credential.held)
                .accessibilityIdentifier("tokens-reveal-\(name)")
            }
            if !credential.facts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(credential.facts) { fact in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fact.label)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
        .accessibilityElement(children: .contain)
    }

    private func revealed(_ text: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("tokens-secret-\(name)")
            FocusButton(.mobileTokensCopy) {
                PlatformPasteboard.copyConcealed(text)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tokens-copy-\(name)")
        }
    }

    private func shows(_ target: TokensReducer.Target) -> Bool {
        if case .shown(target, _) = store.reveal {
            return true
        }
        return false
    }
}
