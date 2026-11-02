import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The pairing screen: PIN entry for a home console, then the running attempt with its progress.
struct PairingView: View {
    /// The screen the user sees, which decides where controller focus starts.
    enum Screen: Hashable {
        /// The PIN field of a home console.
        case enteringPIN

        /// An attempt is starting or running.
        case attempting
    }

    /// The pairing feature.
    let store: StoreOf<PairingFeature>

    /// The screen's input focus.
    let focusedInput: MenuFocusState<EntryFocus?>.Binding

    /// The screen's action focus.
    let focusedAction: MenuFocusState<String?>.Binding

    /// Whether addresses are hidden for streaming.
    let streamerMode: Bool

    @Environment(\.screenLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuNavigator) private var navigator

    /// The screen a pairing state shows.
    ///
    /// - Parameter flow: Where the workflow is.
    /// - Returns: The screen, or `nil` once the workflow has ended.
    static func screen(of flow: PairingFlow) -> Screen? {
        switch flow {
        case .enteringPIN:
            .enteringPIN
        case .ready, .pairing:
            .attempting
        case .paired, .left:
            nil
        }
    }

    /// The view.
    var body: some View {
        switch store.flow {
        case .enteringPIN(let target, let failure):
            pinEntry(target, failure: failure)
        case .ready, .pairing:
            attempting
        case .paired, .left:
            EmptyView()
        }
    }

    @ViewBuilder private func pinEntry(_ target: PairingTarget, failure: PairingFailure?) -> some View {
        let kind = Self.artworkKind(target.kind)
        if !layout.isShort {
            ConsoleArtwork(height: 150, kind: kind)
        }
        FlowTitle(text: "Register your console", detail: detail(target))
        PairingPINEntryView(store: store, focusedInput: focusedInput)
        if let failure {
            Text(PairingFailureMessage.text(for: failure)).font(.caption).foregroundStyle(.red)
        }
        Text(
            target.kind == .ps5
                ? "Settings → System → Remote Play → Link Device"
                : "Settings → Remote Play Connection Settings → Add Device"
        )
        .font(.caption).foregroundStyle(.secondary).padding(.top, 18)
        FlowSecondaryButton(label: "Back", focus: "Back", focusedAction: focusedAction) {
            cancel()
        }
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder private var attempting: some View {
        HStack(spacing: 30) {
            ChiakiLogo(
                size: layout.isShort
                    ? 44
                    : 80,
                isConnecting: true
            )
            ProgressView().controlSize(.small)
            ConsoleArtwork(
                height: layout.isShort
                    ? 64
                    : 140
            )
        }
        .padding(
            .bottom,
            layout.isShort
                ? 10
                : 40
        )
        FlowTitle(text: "A little closer.", detail: "Registering with your console…")
        if let progress = store.flow.attempt?.progress, let reportedAt = store.reportedAt {
            OperationProgressView(progress: TimedProgress(Self.operationProgress(progress), at: reportedAt))
                .padding(.bottom, 16)
        }
        FlowSecondaryButton(label: "Cancel", focus: "Cancel", focusedAction: focusedAction) {
            cancel()
        }
        .keyboardShortcut(.cancelAction)
    }

    private func detail(_ target: PairingTarget) -> String {
        let kind = Self.artworkKind(target.kind).rawValue
        guard !streamerMode, case .atHome(let address, _) = target else {
            return kind
        }
        return "\(kind) at \(address)"
    }

    private func cancel() {
        if focusedInput.wrappedValue != nil {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                focusedInput.wrappedValue = nil
                navigator?.endEditing()
            }
        }
        _ = withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            store.send(.view(.cancel))
        }
    }

    private static func artworkKind(_ kind: ConsoleKind) -> RegistrationFlow.ConsoleKind {
        switch kind {
        case .ps5:
            .ps5
        case .ps4:
            .ps4
        }
    }

    private static func operationProgress(_ progress: PairingProgress) -> OperationProgress {
        OperationProgress(
            step: .pairing(progress.step),
            attempt: progress.attempt,
            elapsedMilliseconds: LogFormat.milliseconds(progress.elapsed),
            wait: progress.wait
        )
    }
}

/// The PIN field and Pair button of a home console's pairing screen.
public struct PairingPINEntryView: View {
    /// The pairing feature; the field is bound to its PIN.
    @Bindable public var store: StoreOf<PairingFeature>

    /// The screen's input focus.
    public let focusedInput: MenuFocusState<EntryFocus?>.Binding

    @Environment(\.screenLayout) private var layout

    /// Creates a pairing pinentry view.
    ///
    /// - Parameters:
    ///   - store: The pairing feature; the field is bound to its PIN.
    ///   - focusedInput: The screen's input focus.
    public init(store: StoreOf<PairingFeature>, focusedInput: MenuFocusState<EntryFocus?>.Binding) {
        self.store = store
        self.focusedInput = focusedInput
    }

    /// The view.
    public var body: some View {
        HStack(spacing: 12) {
            TextField("Eight-digit PIN", text: $store.pin)
                .menuFocusBinding(focusedInput, equals: .pin)
                .font(.title3.monospacedDigit())
                .controllerKeyboard(
                    title: "Pairing PIN",
                    text: $store.pin,
                    isFocused: focusedInput.wrappedValue == .pin,
                    numberPad: true
                )
                .multilineTextAlignment(.center)
                .modifier(GlassInput())
                .accessibilityLabel("Eight-digit pairing PIN")
            FocusButton("Pair console") {
                store.send(.view(.submitPIN))
            }
            .glassControlStyle()
            .controlSize(.large)
            .frame(minHeight: layout.controlSize)
            .menuFocused(focusedInput, equals: .pairConsole)
            .disabled(!store.canSubmitPIN)
        }
        .frame(maxWidth: 400)
    }
}
