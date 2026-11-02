import DesignSystem
import PlatformUI
import SwiftUI

/// Cross-fades between the steps of a flow, such as the pages of sign-in, and ends text entry on the step
/// being left so its field editor does not keep focus.
public struct FlowTransition<Key: Hashable, Content: View>: View {
    private let selection: Key
    private let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuNavigator) private var navigator

    /// Creates the transition.
    ///
    /// - Parameters:
    ///   - selection: The current step; a new value transitions to new content.
    ///   - content: The content of the current step.
    public init(selection: Key, @ViewBuilder content: @escaping () -> Content) {
        self.selection = selection
        self.content = content
    }

    /// The current step, animated with `AppMotion`.
    public var body: some View {
        ZStack {
            content()
                .id(selection)
                .transition(AppMotion.transition(reduced: reduceMotion))
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: selection)
        .onChange(of: selection) { _, _ in
            guard let navigator, let window = WindowFocus.keyWindow, hasTextFocus(
                in: window,
                navigator: navigator
            ) else {
                return
            }
            navigator.endEditing()
        }
    }

    private func hasTextFocus(in window: PlatformWindow, navigator: PlatformMenuNavigator) -> Bool {
        #if os(macOS)
            return window.firstResponder is NSTextView
        #else
            return navigator.isEditingText(in: window)
        #endif
    }
}
