import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The touch Remote Players page: this device's identity and the remembered devices, each renamed or forgotten in
/// place, beside the user's own STUN servers and the media tuning.
struct MobileRemotePlayersSettingsPage: View {
    /// The settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        MobileSettingsForm {
            identity
            peers
        } trailing: {
            stun
            tuning
        }
        .onAppear {
            settings.send(.kakusan(.load))
        }
    }

    private var store: StoreOf<KakusanSettingsFeature> {
        settings.scope(state: \.kakusan, action: \.kakusan)
    }

    private var forgetting: KakusanPeer? {
        switch store.forget {
        case .confirming(let peer), .removing(let peer, _):
            peer
        case .failed, nil:
            nil
        }
    }

    private var identity: some View {
        MobileSettingsGroup(.mobileRemotePlayersThisDevice) {
            switch store.identity {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .mobileRowPadding()
            case .ready(let value):
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(value.fingerprint.lines, id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mobileRowPadding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(.mobileRemotePlayersFingerprint(fingerprint: value.fingerprint.description))
                )
            case .failed:
                KakusanErrorText(text: .mobileRemotePlayersIdentityFailed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
                MobileButtonRow(.mobileRemotePlayersTryAgain) {
                    store.send(.load)
                }
            }
        }
    }

    private var peers: some View {
        MobileSettingsGroup(.mobileRemotePlayersRememberedDevices) {
            switch store.peers {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .mobileRowPadding()
            case .failed:
                KakusanErrorText(text: .mobileRemotePlayersPeersFailed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .ready(let list) where list.isEmpty:
                Text(.mobileRemotePlayersNoPeers)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .ready(let list):
                ForEach(list) { peer in
                    row(peer)
                }
            }
            if case .failed = store.forget {
                KakusanErrorText(text: .mobileRemotePlayersForgetFailed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            }
        }
    }

    @ViewBuilder
    private func row(_ peer: KakusanPeer) -> some View {
        if let rename = store.scope(state: \.rename, action: \.rename.presented),
           rename.subject.publicKey == peer.publicKey {
            renameRow(rename)
        } else if let pending = forgetting, pending.publicKey == peer.publicKey {
            forgetRow(peer)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.nickname)
                        Text(peer.fingerprint.short)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Text(peer.lastSeenAt, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    FocusButton(.mobileRemotePlayersRename) {
                        store.send(.startRename(peer.publicKey))
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.rename != nil)
                    FocusButton(.mobileRemotePlayersForgetDevice, role: .destructive) {
                        store.send(.requestForget(peer.publicKey))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileRowPadding()
        }
    }

    private func renameRow(_ rename: StoreOf<KakusanRememberFeature>) -> some View {
        let name = Binding {
            rename.name
        } set: { value in
            guard value != rename.name else {
                return
            }
            rename.send(.binding(.set(\.name, value)))
        }
        return VStack(alignment: .leading, spacing: 10) {
            MobileTextEntryRow(
                title: .mobileRemotePlayersName,
                prompt: .mobileRemotePlayersName,
                text: name
            )
            .background(.fill.quaternary, in: .rect(cornerRadius: 14))
            HStack(spacing: 10) {
                FocusButton(.commonSave) {
                    rename.send(.view(.controlActivated(.save)))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!rename.canSave)
                FocusButton(.commonCancel) {
                    rename.send(.view(.controlActivated(.cancel)))
                }
                .buttonStyle(.bordered)
            }
            switch rename.phase {
            case .conflict(let holder):
                KakusanErrorText(text: .mobileRemotePlayersNameConflict(name: holder.nickname))
            case .failed:
                KakusanErrorText(text: .mobileRemotePlayersRenameFailed)
            case .editing, .saving:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }

    private func forgetRow(_ peer: KakusanPeer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.mobileRemotePlayersForgetConfirm(name: peer.nickname))
                .font(.body.weight(.semibold))
            HStack(spacing: 10) {
                FocusButton(.commonCancel) {
                    store.send(.cancelForget)
                }
                .buttonStyle(.bordered)
                FocusButton(.mobileRemotePlayersForgetDevice, role: .destructive) {
                    store.send(.confirmForget)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                if case .removing = store.forget {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }

    private var stun: some View {
        MobileSettingsGroup(.mobileRemotePlayersStunServers) {
            stunEditor
            MobileButtonRow(.mobileRemotePlayersApply) {
                store.send(.saveStun)
            }
            .disabled(!store.stunChanged || store.settingsBusy)
            .overlay(alignment: .trailing) {
                if store.stun.busy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            MobileButtonRow(.mobileRemotePlayersUseBuiltInServers) {
                store.send(.restoreDefaultStun)
            }
            .disabled(store.stunDefaultsBlocked)
            switch store.stun {
            case .invalid:
                KakusanErrorText(text: .mobileRemotePlayersStunInvalid)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .failed:
                KakusanErrorText(text: .mobileRemotePlayersStunFailed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .idle, .loading, .ready, .saving:
                EmptyView()
            }
        }
    }

    private var stunDraft: Binding<String> {
        Binding(get: { store.stunDraft }, set: { store.send(.binding(.set(\.stunDraft, $0))) })
    }

    private var stunEditor: some View {
        MobileTextEntryRow(
            title: .mobileRemotePlayersServers,
            prompt: .mobileRemotePlayersServersPrompt,
            text: stunDraft,
            kind: .url,
            multiline: true
        )
    }

    private var tuning: some View {
        MobileSettingsGroup(.mobileRemotePlayersMediaTuning) {
            ForEach(KakusanMediaTuning.Field.allCases, id: \.self) { field in
                tuningRow(field)
            }
            MobileButtonRow(.commonSave) {
                store.send(.saveTuning)
            }
            .disabled(store.tuningSaveBlocked)
            .overlay(alignment: .trailing) {
                if store.tuning.busy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            MobileButtonRow(.mobileRemotePlayersRestoreDefaults) {
                store.send(.restoreDefaultTuning)
            }
            .disabled(store.tuningDefaultsBlocked)
            if store.tuning == .failed {
                KakusanErrorText(text: .mobileRemotePlayersTuningFailed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            }
        }
    }

    private func tuningRow(_ field: KakusanMediaTuning.Field) -> some View {
        let text = Binding(get: { store.tuningDraft[field] }, set: { store.send(.editTuning(field, $0)) })
        return VStack(alignment: .leading, spacing: 4) {
            MobileTextEntryRow(
                title: field.label,
                prompt: .mobileRemotePlayersTuningRangePrompt(
                    lower: String(field.range.lowerBound),
                    upper: String(field.range.upperBound)
                ),
                text: text,
                kind: .number,
                invalid: store.tuningDraft.value(field) == nil
            ) {
                store.send(.saveTuning)
            }
            if store.tuningDraft.value(field) == nil {
                KakusanErrorText(
                    text: .mobileRemotePlayersTuningRangeError(
                        lower: String(field.range.lowerBound),
                        upper: String(field.range.upperBound)
                    )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
