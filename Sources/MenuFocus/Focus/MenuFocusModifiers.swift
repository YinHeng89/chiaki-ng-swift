import SwiftUI

#if os(macOS)
    extension View {
        /// Makes the view a focus stop.
        ///
        /// - Parameter focusable: Whether the view takes focus.
        /// - Returns: The view, focusable when requested.
        public func menuFocusable(_ focusable: Bool = true) -> some View {
            self.focusable(focusable)
        }

        /// Handles presses of a set of keys while the view or a descendant has focus.
        ///
        /// - Parameters:
        ///   - keys: The keys to handle.
        ///   - phases: The phases to handle.
        ///   - action: Returns whether the press was used.
        /// - Returns: The view with the handler attached.
        public func onMenuKeyPress(
            keys: Set<KeyEquivalent>,
            phases: MenuKeyPress.Phases = [.down, .repeat],
            action: @escaping (MenuKeyPress) -> MenuKeyPress.Result
        ) -> some View {
            onKeyPress(keys: keys, phases: phases, action: action)
        }

        /// Handles every key press while the view or a descendant has focus.
        ///
        /// - Parameters:
        ///   - phases: The phases to handle.
        ///   - action: Returns whether the press was used.
        /// - Returns: The view with the handler attached.
        public func onMenuKeyPress(
            phases: MenuKeyPress.Phases = [.down, .repeat],
            action: @escaping (MenuKeyPress) -> MenuKeyPress.Result
        ) -> some View {
            onKeyPress(phases: phases, action: action)
        }

        /// Handles presses of one key while the view or a descendant has focus.
        ///
        /// - Parameters:
        ///   - key: The key to handle.
        ///   - phases: The phases to handle.
        ///   - action: Returns whether the press was used.
        /// - Returns: The view with the handler attached.
        public func onMenuKeyPress(
            _ key: KeyEquivalent,
            phases: MenuKeyPress.Phases = [.down, .repeat],
            action: @escaping (MenuKeyPress) -> MenuKeyPress.Result
        ) -> some View {
            onKeyPress(key, phases: phases, action: action)
        }

        /// Runs an action when Escape or controller back reaches the focused view.
        ///
        /// - Parameter action: The action, or `nil` to handle nothing.
        /// - Returns: The view with the handler attached.
        public func onMenuExitCommand(perform action: (() -> Void)?) -> some View {
            onExitCommand(perform: action)
        }

        /// Runs an action when an arrow key reaches the focused view.
        ///
        /// - Parameter action: Receives the direction, or `nil` to handle nothing.
        /// - Returns: The view with the handler attached.
        public func onMenuMoveCommand(perform action: ((MenuMoveDirection) -> Void)?) -> some View {
            onMoveCommand(perform: action.map { action in
                { direction in
                    if let direction = MenuMoveDirection(direction) {
                        action(direction)
                    }
                }
            })
        }

        /// Groups the view's focus stops so directional moves enter the group as one.
        ///
        /// - Returns: The view as a focus section.
        public func menuFocusSection() -> some View {
            focusSection()
        }

        /// Binds the view's focus to a value of a ``MenuFocusState``.
        ///
        /// Unlike ``SwiftUICore/View/menuFocused(_:equals:)`` this does not mark the view as the highlighted menu
        /// item; use it for containers and text fields that draw their own focus.
        ///
        /// - Parameters:
        ///   - binding: The focus state's binding.
        ///   - value: The value that means this view has focus.
        /// - Returns: The view bound to the focus state.
        public func menuFocusBinding<Value: Hashable>(
            _ binding: MenuFocusState<Value?>.Binding,
            equals value: Value
        ) -> some View {
            focused(binding, equals: value)
        }

        /// Binds the view's focus to a Boolean ``MenuFocusState``.
        ///
        /// - Parameter binding: The focus state's binding.
        /// - Returns: The view bound to the focus state.
        public func menuFocusBinding(_ binding: MenuFocusState<Bool>.Binding) -> some View {
            focused(binding)
        }

        /// Gives a focus state a value when the view appears and nothing is focused yet.
        ///
        /// - Parameters:
        ///   - binding: The focus state's binding.
        ///   - value: The value to focus first.
        /// - Returns: The view with a default focus.
        public func menuDefaultFocus<Value: Hashable>(
            _ binding: MenuFocusState<Value?>.Binding,
            _ value: Value?
        ) -> some View {
            defaultFocus(binding, value)
        }

        /// Binds the view's focus to a value and marks it as the highlighted menu item while focused.
        ///
        /// - Parameters:
        ///   - binding: The focus state's binding.
        ///   - value: The value that means this view has focus.
        /// - Returns: The view bound to the focus state.
        public func menuFocused<Value: Hashable>(
            _ binding: MenuFocusState<Value?>.Binding,
            equals value: Value
        ) -> some View {
            focused(binding, equals: value)
                .environment(\.menuItemFocused, binding.wrappedValue == value)
        }

        /// Binds the view's focus to a Boolean and marks it as the highlighted menu item while focused.
        ///
        /// - Parameter binding: The focus state's binding.
        /// - Returns: The view bound to the focus state.
        public func menuFocused(_ binding: MenuFocusState<Bool>.Binding) -> some View {
            focused(binding)
                .environment(\.menuItemFocused, binding.wrappedValue)
        }
    }
#endif
