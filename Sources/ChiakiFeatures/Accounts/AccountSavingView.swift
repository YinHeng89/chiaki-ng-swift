import MenuFocus
import SwiftUI

/// Shown while an account is being saved or signed in, with a Cancel button.
public struct AccountSavingView: View {
    /// The screen's action focus.
    public let focusedAction: MenuFocusState<String?>.Binding

    /// Abandons saving the account.
    public let cancel: () -> Void

    /// Creates an account saving view.
    ///
    /// - Parameters:
    ///   - focusedAction: The screen's action focus.
    ///   - cancel: Abandons saving the account.
    public init(focusedAction: MenuFocusState<String?>.Binding, cancel: @escaping () -> Void) {
        self.focusedAction = focusedAction
        self.cancel = cancel
    }

    /// The view.
    public var body: some View {
        VStack(spacing: 24) {
            ProgressView("Saving your account…")
            FlowSecondaryButton(
                label: "Cancel",
                focus: "Cancel",
                focusedAction: focusedAction,
                perform: cancel
            )
            .keyboardShortcut(.cancelAction)
        }
    }
}
