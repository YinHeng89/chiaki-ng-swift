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
                Text("This device").font(.subheadline.weight(.semibold))
                ProgressView().controlSize(.small)
            }
        case .ready(let value):
            KakusanFingerprintView(title: "This device", fingerprint: value.fingerprint)
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("This device").font(.subheadline.weight(.semibold))
                KakusanErrorText(text: "Couldn’t load this device’s identity")
                FocusButton("Try again") {
                    store.send(.load)
                }
                .glassControlStyle()
            }
        }
    }

    @ViewBuilder
    private var peers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remembered devices").font(.subheadline.weight(.semibold))
            switch store.peers {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .failed:
                KakusanErrorText(text: "Couldn’t load remembered devices")
            case .ready(let list) where list.isEmpty:
                Text("No remembered devices")
                    .foregroundStyle(.secondary)
            case .ready(let list):
                ForEach(list) { peer in
                    row(peer)
                }
            }
            if case .failed = store.forget {
                KakusanErrorText(text: "Couldn’t forget that device")
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
                FocusButton("Rename") {
                    store.send(.startRename(peer.publicKey))
                }
                .glassControlStyle()
                .menuFocused($focus, equals: .renameButton(peer.publicKey))
                .disabled(store.rename != nil)
                FocusButton("Forget device", role: .destructive) {
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
                TextField("Name", text: name)
                    .textFieldStyle(.roundedBorder)
                    .menuFocusBinding($focus, equals: .rename)
                    .onSubmit {
                        rename.send(.view(.nameSubmitted))
                    }
                    .controllerKeyboard(
                        title: "Name",
                        text: name,
                        isFocused: focus == .rename
                    )
                FocusButton("Save") {
                    rename.send(.view(.controlActivated(.save)))
                }
                .glassProminentControlStyle()
                .disabled(!rename.canSave)
                FocusButton("Cancel") {
                    rename.send(.view(.controlActivated(.cancel)))
                }
                .glassControlStyle()
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
        .padding(12)
        .glassPanel(.small)
    }

    private var stun: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your own STUN servers").font(.subheadline.weight(.semibold))
            stunEditor
                .padding(12)
                .glassPanel(.small)
                .accessibilityLabel("Your own STUN servers")
            HStack(spacing: 10) {
                FocusButton("Apply") {
                    store.send(.saveStun)
                }
                .glassControlStyle()
                .disabled(!store.stunChanged || store.settingsBusy)
                FocusButton("Use built-in servers") {
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
                KakusanErrorText(text: "Use host:port, one server per line, up to eight")
            case .failed:
                KakusanErrorText(text: "Couldn’t load or save STUN servers")
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
            Text("Forget \(peer.nickname)?")
                .font(.callout.weight(.semibold))
            Spacer(minLength: 12)
            FocusButton("Cancel") {
                store.send(.cancelForget)
            }
            .glassControlStyle()
            .menuFocused($focus, equals: .forgetCancel(peer.publicKey))
            FocusButton("Forget device", role: .destructive) {
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
                    title: "Your own STUN servers",
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
        Text("Leave empty to use the built-in servers")
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
            Text("Media tuning").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(KakusanMediaTuning.Field.allCases, id: \.self) { field in
                    row(field)
                }
            }
            .padding(12)
            .frame(maxWidth: 640, alignment: .leading)
            .glassPanel(.small)
            HStack(spacing: 10) {
                FocusButton("Save") {
                    store.send(.saveTuning)
                }
                .glassControlStyle()
                .disabled(store.tuningSaveBlocked)
                FocusButton("Restore defaults") {
                    store.send(.restoreDefaultTuning)
                }
                .glassControlStyle()
                .disabled(store.tuningDefaultsBlocked)
                if store.tuning.busy {
                    ProgressView().controlSize(.small)
                }
            }
            if store.tuning == .failed {
                KakusanErrorText(text: "Couldn’t load or save media tuning")
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
                KakusanErrorText(text: "\(field.range.lowerBound) to \(field.range.upperBound)")
            }
        }
    }

    private func text(_ field: KakusanMediaTuning.Field) -> Binding<String> {
        Binding(get: { store.tuningDraft[field] }, set: { store.send(.editTuning(field, $0)) })
    }
}
