import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// Adds an account by its Base64 PSN account id, for local play without a sign-in.
///
/// The fields are bound; the account id is validated by `ChiakiModels/AccountID/init(typed:)`, the one
/// typed-account-id validator. Submitting hands the validated id upward; the parent saves it.
@Reducer
public struct AccountIDEntryFeature {
    /// The entry screen's fields.
    @ObservableState
    public struct State: Equatable {
        /// The optional display name.
        public var name = ""

        /// The typed Base64 account id.
        public var accountID = ""

        /// Opens the screen with empty fields.
        public init() {}

        /// The typed account id, when it is valid.
        public var validAccountID: AccountID? {
            AccountID(typed: accountID)
        }

        /// The name to save: the typed name, or a default when none was typed.
        public var savedName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? String(localized: .accountsAccountIdDefaultName)
                : trimmed
        }
    }

    /// Everything the entry screen reacts to.
    public enum Action: BindableAction, Equatable {
        /// A change to a bound field.
        case binding(BindingAction<State>)

        /// Something the user did.
        case view(View)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// Saves the account.
            case submit

            /// Leaves the screen.
            case back
        }

        /// What the entry reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The user submitted a valid account id under a name.
            case submitted(name: String, account: AccountID)

            /// The user left.
            case left
        }
    }

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none
            case .view(.submit):
                guard let account = state.validAccountID else {
                    return .none
                }
                return .send(.delegate(.submitted(name: state.savedName, account: account)))
            case .view(.back):
                state = State()
                return .send(.delegate(.left))
            }
        }
    }
}

/// The account id screen of ``AccountIDEntryFeature``: name and account id fields, the save button, why the
/// last save failed, and Back.
public struct AccountIDEntryView: View {
    /// The entry feature whose name and account id the text fields edit.
    @Bindable var store: StoreOf<AccountIDEntryFeature>
    /// Why the last save failed, shown under the fields; `nil` hides the message.
    let failure: AccountsFailure?
    /// The screen's controller focus, shared with the fields, the create button and Back.
    let focusedInput: MenuFocusState<EntryFocus?>.Binding

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - store: The entry feature; the fields are bound to it.
    ///   - failure: Why the last save failed, if it did.
    ///   - focusedInput: The screen's focus.
    public init(
        store: StoreOf<AccountIDEntryFeature>,
        failure: AccountsFailure?,
        focusedInput: MenuFocusState<EntryFocus?>.Binding
    ) {
        self.store = store
        self.failure = failure
        self.focusedInput = focusedInput
    }

    /// The screen.
    public var body: some View {
        VStack(spacing: 0) {
            FlowTitle(text: .accountsAccountIdTitle, detail: .accountsAccountIdDetail)
            fields
            if let failure {
                Text(AccountsFailureMessage.text(for: failure))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                    .padding(.top, 18)
            }
            FlowSecondaryButton(
                label: .commonBack,
                focus: EntryFocus.accountIDBack,
                focusedAction: focusedInput
            ) {
                store.send(.view(.back))
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var fields: some View {
        VStack(spacing: 16) {
            TextField(.accountsAccountIdNamePlaceholder, text: $store.name)
                .menuFocusBinding(focusedInput, equals: .accountName)
                .controllerKeyboard(
                    title: .accountsAccountIdNameKeyboard,
                    text: $store.name,
                    isFocused: focusedInput.wrappedValue == .accountName
                )
                .modifier(GlassInput())
            TextField(.accountsAccountIdIdPlaceholder, text: $store.accountID)
                .menuFocusBinding(focusedInput, equals: .accountID)
                .controllerKeyboard(
                    title: .accountsAccountIdIdKeyboard,
                    text: $store.accountID,
                    isFocused: focusedInput.wrappedValue == .accountID
                )
                .modifier(GlassInput())
            FocusButton(.accountsAccountIdCreate) {
                store.send(.view(.submit))
            }
            .glassControlStyle()
            .controlSize(.large)
            .menuFocused(focusedInput, equals: .createProfile)
            .disabled(store.validAccountID == nil)
        }
        .frame(maxWidth: 280)
    }
}
