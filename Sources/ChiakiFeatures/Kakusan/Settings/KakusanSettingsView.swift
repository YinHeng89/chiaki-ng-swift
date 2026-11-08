import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The Kakusan settings: this device's identity, remembered devices, STUN servers and media tuning.
struct KakusanSettingsView: View {
    @Environment(\.menuNavigator) private var navigator

    /// A control on the screen that controller focus can rest on.
    enum Field: Hashable {
        /// The rename field of the device being renamed.
        case rename
        /// The STUN server field.
        case stun
        /// The rename button of a remembered device.
        case renameButton(KakusanPublicKey)
        /// The forget button of a remembered device.
        case forgetButton(KakusanPublicKey)
        /// The cancel button while forgetting a remembered device.
        case forgetCancel(KakusanPublicKey)
        /// A media tuning row.
        case tuning(KakusanMediaTuning.Field)
    }

    /// The settings feature.
    @Bindable var store: StoreOf<KakusanSettingsFeature>
    @MenuFocusState private var focus: Field?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hostWindow: PlatformWindow?
    @State private var backHandlerID: MenuHandlerID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            identity
            peers
            stun
            KakusanTuningSection(store: store, focus: $focus)
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onChange(of: rowEditing, initial: true) { _, editing in
            updateBackHandler(editing)
        }
        .onDisappear {
            updateBackHandler(false)
        }
        .onChange(of: store.rename?.subject.publicKey) { previous, current in
            if current != nil {
                refocus(.rename)
            } else if let previous {
                refocus(.renameButton(previous))
            }
        }
        .onChange(of: forgetting?.publicKey) { previous, current in
            if let current {
                refocus(.forgetCancel(current))
            } else if let previous {
                refocus(fallbackAfterForget(previous))
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        switch store.identity {
        case .idle, .loading:
            HStack(spacing: 10) {
                Text(.kakusanSettingsThisDevice).font(.subheadline.weight(.semibold))
                ProgressView().controlSize(.small)
            }
        case .ready(let value):
            KakusanFingerprintView(title: .kakusanSettingsThisDevice, fingerprint: value.fingerprint)
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text(.kakusanSettingsThisDevice).font(.subheadline.weight(.semibold))
                KakusanErrorText(text: .kakusanSettingsIdentityFailed)
                FocusButton(.commonTryAgain) {
                    store.send(.load)
                }
                .glassControlStyle()
            }
        }
    }

    @ViewBuilder
    private var peers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.kakusanSettingsRememberedDevices).font(.subheadline.weight(.semibold))
            switch store.peers {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .failed:
                KakusanErrorText(text: .kakusanSettingsPeersFailed)
            case .ready(let list) where list.isEmpty:
                Text(.kakusanSettingsNoPeers)
                    .foregroundStyle(.secondary)
            case .ready(let list):
                ForEach(list) { peer in
                    row(peer)
                }
            }
            if case .failed = store.forget {
                KakusanErrorText(text: .kakusanSettingsForgetFailed)
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
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(peer.nickname)
                        .font(.callout.weight(.semibold))
                    Text(peer.fingerprint.short)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(peer.lastSeenAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusButton(.kakusanSettingsRename) {
                    store.send(.startRename(peer.publicKey))
                }
                .glassControlStyle()
                .menuFocused($focus, equals: .renameButton(peer.publicKey))
                .disabled(store.rename != nil)
                FocusButton(.kakusanSettingsForgetDevice, role: .destructive) {
                    store.send(.requestForget(peer.publicKey))
                }
                .glassControlStyle()
                .menuFocused($focus, equals: .forgetButton(peer.publicKey))
            }
            .padding(12)
            .glassPanel(.small)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField(.kakusanRememberName, text: name)
                    .textFieldStyle(.roundedBorder)
                    .menuFocusBinding($focus, equals: .rename)
                    .onSubmit {
                        rename.send(.view(.nameSubmitted))
                    }
                    .controllerKeyboard(
                        title: .kakusanRememberName,
                        text: name,
                        isFocused: focus == .rename
                    )
                FocusButton(.commonSave) {
                    rename.send(.view(.controlActivated(.save)))
                }
                .glassProminentControlStyle()
                .disabled(!rename.canSave)
                FocusButton(.commonCancel) {
                    rename.send(.view(.controlActivated(.cancel)))
                }
                .glassControlStyle()
            }
            switch rename.phase {
            case .conflict(let holder):
                KakusanErrorText(text: .kakusanRememberNameConflict(name: holder.nickname))
            case .failed:
                KakusanErrorText(text: .kakusanSettingsRenameFailed)
            case .editing, .saving:
                EmptyView()
            }
        }
        .padding(12)
        .glassPanel(.small)
    }

    private var stun: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.kakusanSettingsStunServers).font(.subheadline.weight(.semibold))
            stunEditor
                .padding(12)
                .glassPanel(.small)
                .accessibilityLabel(.kakusanSettingsStunServers)
            HStack(spacing: 10) {
                FocusButton(.kakusanSettingsApply) {
                    store.send(.saveStun)
                }
                .glassControlStyle()
                .disabled(!store.stunChanged || store.settingsBusy)
                FocusButton(.kakusanSettingsUseBuiltIn) {
                    store.send(.restoreDefaultStun)
                }
                .glassControlStyle()
                .disabled(store.stunDefaultsBlocked)
                if store.stun.busy {
                    ProgressView().controlSize(.small)
                }
            }
            switch store.stun {
            case .invalid:
                KakusanErrorText(text: .kakusanSettingsStunInvalid)
            case .failed:
                KakusanErrorText(text: .kakusanSettingsStunFailed)
            case .idle, .loading, .ready, .saving:
                EmptyView()
            }
        }
    }

    private var forgetting: KakusanPeer? {
        switch store.forget {
        case .confirming(let peer), .removing(let peer, _):
            peer
        case .failed, nil:
            nil
        }
    }

    private func forgetRow(_ peer: KakusanPeer) -> some View {
        HStack(spacing: 10) {
            Text(.kakusanSettingsForgetConfirm(name: peer.nickname))
                .font(.callout.weight(.semibold))
            Spacer(minLength: 12)
            FocusButton(.commonCancel) {
                store.send(.cancelForget)
            }
            .glassControlStyle()
            .menuFocused($focus, equals: .forgetCancel(peer.publicKey))
            FocusButton(.kakusanSettingsForgetDevice, role: .destructive) {
                store.send(.confirmForget)
            }
            .glassProminentControlStyle()
            .tint(.red)
            if case .removing = store.forget {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .glassPanel(.small)
    }
}

extension KakusanSettingsView {
    @ViewBuilder
    private var stunEditor: some View {
        if isEnabled {
            TextEditor(text: $store.stunDraft)
                .scrollContentBackground(.hidden)
                .font(.callout.monospaced())
                .frame(minHeight: 44, maxHeight: 140)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .topLeading) {
                    if store.stunDraft.isEmpty {
                        stunPlaceholder
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .menuFocusBinding($focus, equals: .stun)
                .controllerKeyboard(
                    title: .kakusanSettingsStunServers,
                    text: $store.stunDraft,
                    isFocused: focus == .stun,
                    allowsNewline: true
                )
        } else {
            Group {
                if store.stunDraft.isEmpty {
                    stunPlaceholder
                } else {
                    Text(store.stunDraft).font(.callout.monospaced())
                }
            }
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 140, alignment: .topLeading)
        }
    }

    private var stunPlaceholder: some View {
        Text(.kakusanSettingsStunPlaceholder)
            .font(.callout.monospaced())
            .foregroundStyle(.tertiary)
    }

    private var rowEditing: Bool {
        store.rename != nil || forgetting != nil
    }

    private func updateBackHandler(_ active: Bool) {
        if active, backHandlerID == nil {
            backHandlerID = navigator?.handlers.registerBack { window in
                guard window === hostWindow, !(navigator?.isEditingText(in: window) ?? false) else {
                    return false
                }
                if store.rename != nil {
                    store.send(.rename(.presented(.view(.backPressed))))
                    return true
                }
                if case .confirming = store.forget {
                    store.send(.cancelForget)
                    return true
                }
                return false
            }
        } else if !active, let backHandlerID {
            navigator?.handlers.unregister(backHandlerID)
            self.backHandlerID = nil
        }
    }

    private func refocus(_ field: Field) {
        Task { @MainActor in
            await Task.yield()
            focus = field
        }
    }

    private func fallbackAfterForget(_ key: KakusanPublicKey) -> Field {
        guard case .ready(let list) = store.peers else {
            return .stun
        }
        if list.contains(where: { $0.publicKey == key }) {
            return .forgetButton(key)
        }
        return list.first.map { .renameButton($0.publicKey) } ?? .stun
    }
}

/// The media tuning rows of the Kakusan settings.
private struct KakusanTuningSection: View {
    /// The settings feature that owns the tuning draft.
    let store: StoreOf<KakusanSettingsFeature>
    /// The settings screen's controller focus.
    let focus: MenuFocusState<KakusanSettingsView.Field?>.Binding
    @Environment(\.screenLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.kakusanSettingsMediaTuning).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(KakusanMediaTuning.Field.allCases, id: \.self) { field in
                    row(field)
                }
            }
            .padding(12)
            .frame(maxWidth: 640, alignment: .leading)
            .glassPanel(.small)
            HStack(spacing: 10) {
                FocusButton(.commonSave) {
                    store.send(.saveTuning)
                }
                .glassControlStyle()
                .disabled(store.tuningSaveBlocked)
                FocusButton(.kakusanSettingsRestoreDefaults) {
                    store.send(.restoreDefaultTuning)
                }
                .glassControlStyle()
                .disabled(store.tuningDefaultsBlocked)
                if store.tuning.busy {
                    ProgressView().controlSize(.small)
                }
            }
            if store.tuning == .failed {
                KakusanErrorText(text: .kakusanSettingsTuningFailed)
            }
        }
    }

    private func row(_ field: KakusanMediaTuning.Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Text(field.label)
                    .font(.callout)
                Spacer(minLength: 12)
                TextField("", text: text(field))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
                    .frame(minHeight: layout.controlSize)
                    .menuFocusBinding(focus, equals: .tuning(field))
                    .onSubmit {
                        store.send(.saveTuning)
                    }
                    .controllerKeyboard(
                        title: field.label,
                        text: text(field),
                        isFocused: focus.wrappedValue == .tuning(field),
                        numberPad: true
                    )
                    .accessibilityLabel(field.label)
            }
            if store.tuningDraft.value(field) == nil {
                KakusanErrorText(text: .kakusanSettingsTuningRange(
                    lower: field.range.lowerBound,
                    upper: field.range.upperBound
                ))
            }
        }
    }

    private func text(_ field: KakusanMediaTuning.Field) -> Binding<String> {
        Binding(get: { store.tuningDraft[field] }, set: { store.send(.editTuning(field, $0)) })
    }
}
