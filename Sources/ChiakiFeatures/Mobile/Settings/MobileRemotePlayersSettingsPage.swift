import ChiakiModels
import ComposableArchitecture
import DesignSystem
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
        MobileSettingsGroup("This device") {
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
                .accessibilityLabel("Fingerprint \(value.fingerprint.description)")
            case .failed:
                KakusanErrorText(text: "Couldn’t load this device’s identity")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
                MobileButtonRow("Try Again") {
                    store.send(.load)
                }
            }
        }
    }

    private var peers: some View {
        MobileSettingsGroup("Remembered devices") {
            switch store.peers {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .mobileRowPadding()
            case .failed:
                KakusanErrorText(text: "Couldn’t load remembered devices")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .ready(let list) where list.isEmpty:
                Text("No remembered devices")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .ready(let list):
                ForEach(list) { peer in
                    row(peer)
                }
            }
            if case .failed = store.forget {
                KakusanErrorText(text: "Couldn’t forget that device")
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
                    Button("Rename") {
                        store.send(.startRename(peer.publicKey))
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.rename != nil)
                    Button("Forget Device", role: .destructive) {
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
            MobileTextEntryRow(title: "Name", prompt: "Name", text: name)
                .background(.fill.quaternary, in: .rect(cornerRadius: 14))
            HStack(spacing: 10) {
                Button("Save") {
                    rename.send(.view(.controlActivated(.save)))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!rename.canSave)
                Button("Cancel") {
                    rename.send(.view(.controlActivated(.cancel)))
                }
                .buttonStyle(.bordered)
            }
            switch rename.phase {
            case .conflict(let holder):
                KakusanErrorText(text: "Another device is saved as \(holder.nickname)")
            case .failed:
                KakusanErrorText(text: "Couldn’t rename this device")
            case .editing, .saving:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }

    private func forgetRow(_ peer: KakusanPeer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Forget \(peer.nickname)?")
                .font(.body.weight(.semibold))
            HStack(spacing: 10) {
                Button("Cancel") {
                    store.send(.cancelForget)
                }
                .buttonStyle(.bordered)
                Button("Forget Device", role: .destructive) {
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
        MobileSettingsGroup("Your own STUN servers") {
            stunEditor
            MobileButtonRow("Apply") {
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
            MobileButtonRow("Use Built-In Servers") {
                store.send(.restoreDefaultStun)
            }
            .disabled(store.stunDefaultsBlocked)
            switch store.stun {
            case .invalid:
                KakusanErrorText(text: "Use host:port, one server per line, up to eight")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            case .failed:
                KakusanErrorText(text: "Couldn’t load or save STUN servers")
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
            title: "Servers",
            prompt: "Built-in servers",
            text: stunDraft,
            kind: .url,
            multiline: true
        )
    }

    private var tuning: some View {
        MobileSettingsGroup("Media tuning") {
            ForEach(KakusanMediaTuning.Field.allCases, id: \.self) { field in
                tuningRow(field)
            }
            MobileButtonRow("Save") {
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
            MobileButtonRow("Restore Defaults") {
                store.send(.restoreDefaultTuning)
            }
            .disabled(store.tuningDefaultsBlocked)
            if store.tuning == .failed {
                KakusanErrorText(text: "Couldn’t load or save media tuning")
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
                prompt: "\(field.range.lowerBound)–\(field.range.upperBound)",
                text: text,
                kind: .number,
                invalid: store.tuningDraft.value(field) == nil
            ) {
                store.send(.saveTuning)
            }
            if store.tuningDraft.value(field) == nil {
                KakusanErrorText(text: "\(field.range.lowerBound) to \(field.range.upperBound)")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
}
