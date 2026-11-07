import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// Names a device: remembers a peer verified in the running session, or renames a remembered one.
///
/// The name is normalised as it is typed, so Save is offered only for a name the core accepts. A name another
/// device holds comes back as ``Phase/conflict(_:)``; a verified peer can then take it with Replace. Every save
/// carries the id of the operation that started it. The card reports upward only through
/// ``Action/Delegate/finished(_:)``.
@Reducer
public struct KakusanRememberFeature {
    /// The device being named.
    public enum Subject: Equatable, Sendable {
        /// A peer verified in the running session, not yet remembered.
        case verified(KakusanIdentity)
        /// A remembered device being renamed.
        case remembered(KakusanPeer)

        /// The device's public key.
        public var publicKey: KakusanPublicKey {
            switch self {
            case .verified(let peer):
                peer.publicKey
            case .remembered(let peer):
                peer.publicKey
            }
        }

        /// The device's fingerprint.
        public var fingerprint: KakusanFingerprint {
            switch self {
            case .verified(let peer):
                peer.fingerprint
            case .remembered(let peer):
                peer.fingerprint
            }
        }
    }

    /// Where naming is.
    public enum Phase: Equatable, Sendable {
        /// The name is being typed.
        case editing
        /// The operation with the id is saving the name.
        case saving(UUID)
        /// Another device already has the name.
        case conflict(KakusanPeer)
        /// Saving failed.
        case failed
    }

    /// The naming card's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The device being named.
        public let subject: Subject

        /// The name as typed.
        public var name: String

        /// The name as the core would save it, or `nil` when it cannot be a nickname.
        public internal(set) var normalised: String?

        /// Where naming is.
        public internal(set) var phase = Phase.editing

        /// The card's controls and the selected one.
        public internal(set) var controls = KakusanControlGrid([[.name], [.cancel, .save]])

        /// Counts requests to show the on-screen keyboard for the name.
        public internal(set) var keyboardRequest = 0

        /// Opens the card.
        ///
        /// - Parameters:
        ///   - subject: The device being named.
        ///   - name: The name to start from.
        ///   - normalised: The starting name as the core would save it.
        public init(subject: Subject, name: String = "", normalised: String? = nil) {
            self.subject = subject
            self.name = name
            self.normalised = normalised
        }

        /// Whether the typed name can be saved now.
        public var canSave: Bool {
            normalised != nil && !saving
        }

        /// Whether a save is running.
        public var saving: Bool {
            if case .saving = phase {
                return true
            }
            return false
        }
    }

    /// Everything the naming card reacts to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to the name.
        case binding(BindingAction<State>)
        /// Something the user did on the card.
        case view(View)
        /// A save ended with the core's answer.
        case saved(UUID, KakusanRememberResult)
        /// A save failed.
        case failed(UUID)
        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did on the card.
        @CasePathable
        public enum View: Equatable, Sendable {
            /// A control was activated.
            case controlActivated(KakusanControl)
            /// Back was pressed.
            case backPressed
            /// Controller navigation moved the selection.
            case moved(KakusanGridStep)
            /// The name field was submitted.
            case nameSubmitted
        }

        /// What the card reports to its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// Naming ended with the saved device, or `nil` when the user cancelled.
            case finished(KakusanPeer?)
        }
    }

    @Dependency(\.kakusan) private var kakusan
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.name):
                state.name = String(state.name.prefix(KakusanPeer.maximumNicknameLength))
                state.normalised = kakusan.nickname(state.name)
                if !state.saving {
                    state.phase = .editing
                }
                state.controls.show(Self.rows(state.phase))
                return .none
            case .binding, .delegate:
                return .none
            case .view(.moved(let step)):
                state.controls.move(step)
                return .none
            case .view(.controlActivated(let control)):
                return activate(control, in: &state)
            case .view(.nameSubmitted):
                return activate(.save, in: &state)
            case .view(.backPressed):
                return activate(.cancel, in: &state)
            case let .saved(operation, result):
                guard state.phase == .saving(operation) else {
                    return .none
                }
                switch result {
                case .saved(let peer):
                    return .send(.delegate(.finished(peer)))
                case .nicknameTaken(let holder):
                    state.phase = .conflict(holder)
                    state.controls.show(Self.rows(state.phase), preferring: .replace)
                    return .none
                }
            case .failed(let operation):
                guard state.phase == .saving(operation) else {
                    return .none
                }
                state.phase = .failed
                return .none
            }
        }
    }

    private static func rows(_ phase: Phase) -> [[KakusanControl]] {
        if case .conflict = phase {
            return [[.name], [.cancel, .replace, .save]]
        }
        return [[.name], [.cancel, .save]]
    }

    private func activate(_ control: KakusanControl, in state: inout State) -> Effect<Action> {
        state.controls.select(control)
        switch control {
        case .name:
            state.keyboardRequest += 1
            return .none
        case .save:
            guard state.canSave else {
                return .none
            }
            return save(&state, replacing: false)
        case .replace:
            guard case .conflict = state.phase, case .verified = state.subject else {
                return .none
            }
            return save(&state, replacing: true)
        case .cancel:
            guard !state.saving else {
                return .none
            }
            return .send(.delegate(.finished(nil)))
        default:
            return .none
        }
    }

    private func save(_ state: inout State, replacing: Bool) -> Effect<Action> {
        guard let name = state.normalised else {
            return .none
        }
        let operation = uuid()
        let subject = state.subject
        state.phase = .saving(operation)
        return .run { [kakusan] send in
            do {
                switch subject {
                case .verified(let peer):
                    await send(.saved(operation, try await kakusan.remember(peer, name, replacing)))
                case .remembered(let peer):
                    await send(.saved(operation, try await kakusan.rename(peer.publicKey, name)))
                }
            } catch {
                await send(.failed(operation))
            }
        }
    }
}

/// The card that names a verified device.
struct KakusanRememberCard: View {
    /// The naming feature.
    @Bindable var store: StoreOf<KakusanRememberFeature>
    /// The card's heading.
    let title: LocalizedStringResource
    /// Whether the window behind the card is dimmed.
    var dims = true
    @State private var hostWindow: PlatformWindow?
    @MenuFocusState private var nameFocused: Bool

    var body: some View {
        KakusanModal(
            width: 480,
            dims: dims,
            controls: store.controls,
            move: { store.send(.view(.moved($0))) },
            activate: { store.send(.view(.controlActivated($0))) },
            back: { store.send(.view(.backPressed)) },
            content: {
                KakusanHeader(symbol: "person.crop.circle.badge.checkmark", title: title)
                KakusanFingerprintView(
                    title: .kakusanInviteDeviceFingerprint,
                    fingerprint: store.subject.fingerprint
                )
                nameField
                switch store.phase {
                case .conflict(let holder):
                    KakusanErrorText(text: .kakusanRememberNameConflict(name: holder.nickname))
                case .failed:
                    KakusanErrorText(text: .kakusanRememberSaveFailed)
                case .editing, .saving:
                    EmptyView()
                }
                HStack(spacing: 10) {
                    button(.commonCancel, .cancel)
                    if store.controls.shows(.replace) {
                        button(.kakusanRememberReplace, .replace, destructive: true)
                    }
                    button(.commonSave, .save, prominent: true)
                        .disabled(!store.canSave)
                }
            }
        )
        .background(WindowAccessor { hostWindow = $0 })
    }

    private var name: Binding<String> {
        Binding {
            store.name
        } set: { value in
            guard value != store.name else {
                return
            }
            store.send(.binding(.set(\.name, value)))
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.kakusanRememberName)
                .font(.headline)
            TextField(.kakusanRememberName, text: name)
                .textFieldStyle(.plain)
                .menuFocusBinding($nameFocused)
                .onSubmit {
                    store.send(.view(.nameSubmitted))
                }
                .padding(12)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(store.controls.selection == .name
                            ? Palette.accent
                            : Color.clear, lineWidth: 2)
                }
                .controllerKeyboard(
                    title: .kakusanRememberName,
                    text: name,
                    isFocused: nameFocused || store.controls.selection == .name,
                    presentationRequest: store.keyboardRequest,
                    presentationWindow: hostWindow
                )
        }
    }

    private func button(
        _ title: LocalizedStringResource,
        _ control: KakusanControl,
        prominent: Bool = false,
        destructive: Bool = false
    ) -> some View {
        KakusanActionButton(
            title: title,
            prominent: prominent,
            destructive: destructive,
            focused: store.controls.selection == control
        ) {
            store.send(.view(.controlActivated(control)))
        }
    }
}
