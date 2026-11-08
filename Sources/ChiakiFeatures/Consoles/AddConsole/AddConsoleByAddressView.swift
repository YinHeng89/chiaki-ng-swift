import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The add-console screen of an account added by account id: the console is found by its address only.
public struct AddConsoleByAddressView: View {
    /// The add-console feature.
    public let store: StoreOf<AddConsoleFeature>

    /// Why the last pairing could not start or ended without a console.
    public let failure: PairingFailure?

    /// The screen's input focus.
    public let focusedInput: MenuFocusState<EntryFocus?>.Binding

    /// The screen's action focus.
    public let focusedAction: MenuFocusState<String?>.Binding

    /// The focus of the generation switch.
    public let kindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding

    @Environment(\.screenLayout) private var layout

    /// Creates an add console by address view.
    ///
    /// - Parameters:
    ///   - store: The add-console feature.
    ///   - failure: Why the last pairing could not start or ended without a console.
    ///   - focusedInput: The screen's input focus.
    ///   - focusedAction: The screen's action focus.
    ///   - kindFocus: The focus of the generation switch.
    public init(
        store: StoreOf<AddConsoleFeature>,
        failure: PairingFailure?,
        focusedInput: MenuFocusState<EntryFocus?>.Binding,
        focusedAction: MenuFocusState<String?>.Binding,
        kindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding
    ) {
        self.store = store
        self.failure = failure
        self.focusedInput = focusedInput
        self.focusedAction = focusedAction
        self.kindFocus = kindFocus
    }

    /// The view.
    public var body: some View {
        if !layout.isShort {
            ConsoleArtwork(height: 150, kind: .ps5)
        }
        FlowTitle(text: .consolesAddByAddressTitle, detail: .consolesAddByAddressDetail)
        ConsoleAddressEntryView(store: store, focusedInput: focusedInput, kindFocus: kindFocus)
        if let failure {
            Text(PairingFailureMessage.text(for: failure))
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 12)
        }
        FlowSecondaryButton(label: .commonBack, focus: "Back", focusedAction: focusedAction) {
            store.send(.view(.back))
        }
        .keyboardShortcut(.cancelAction)
    }
}

/// The address field, generation switch and Continue button of the add-console screen of an account added by
/// account id.
public struct ConsoleAddressEntryView: View {
    /// The add-console feature; the fields are bound to it.
    @Bindable public var store: StoreOf<AddConsoleFeature>

    /// The screen's input focus.
    public let focusedInput: MenuFocusState<EntryFocus?>.Binding

    /// The focus of the generation switch.
    public let kindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding

    /// The fields.
    public var body: some View {
        VStack(spacing: 18) {
            TextField(.consolesAddressPlaceholder, text: $store.address)
                .streamerHiddenField(store.address)
                .menuFocusBinding(focusedInput, equals: .consoleAddress)
                .controllerKeyboard(
                    title: .consolesAddressKeyboardTitle,
                    text: $store.address,
                    isFocused: focusedInput.wrappedValue == .consoleAddress
                )
                .modifier(GlassInput())
                .accessibilityLabel(.consolesAddressAccessibility)
            FocusableSegments(
                options: RegistrationFlow.ConsoleKind.allCases,
                title: { $0 == .ps5
                    ? .consolesKindPs5
                    : .consolesKindPs4 },
                selection: $store.kind,
                focus: kindFocus
            )
            FocusButton(.commonContinue) {
                store.send(.view(.submitAddress))
            }
            .glassControlStyle()
            .controlSize(.large)
            .menuFocused(focusedInput, equals: .consoleContinue)
            .disabled(store.validAddress == nil)
        }
        .frame(maxWidth: 280)
    }
}
