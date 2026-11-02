#if os(iOS)
    import SwiftUI

    extension View {
        /// Makes the view a focus stop.
        ///
        /// - Parameter focusable: Whether the view takes focus.
        /// - Returns: The view as a leaf of its focus stop.
        public func menuFocusable(_ focusable: Bool = true) -> some View {
            modifier(MenuFocusableLeaf(focusable: focusable))
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
            modifier(MenuFocusNodeHost { node in
                node.keyHandlers.append(.init(keys: keys, phases: phases, action: action))
            })
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
            modifier(MenuFocusNodeHost { node in
                node.keyHandlers.append(.init(keys: nil, phases: phases, action: action))
            })
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
            modifier(MenuFocusNodeHost { node in
                node.keyHandlers.append(.init(keys: [key], phases: phases, action: action))
            })
        }

        /// Runs an action when controller back reaches the focused view.
        ///
        /// - Parameter action: The action, or `nil` to handle nothing.
        /// - Returns: The view with the handler attached.
        public func onMenuExitCommand(perform action: (() -> Void)?) -> some View {
            modifier(MenuFocusNodeHost { node in
                node.exit = action
            })
        }

        /// Runs an action when a direction reaches the focused view.
        ///
        /// - Parameter action: Receives the direction, or `nil` to handle nothing.
        /// - Returns: The view with the handler attached.
        public func onMenuMoveCommand(perform action: ((MenuMoveDirection) -> Void)?) -> some View {
            modifier(MenuFocusNodeHost { node in
                node.move = action
            })
        }

        /// Groups the view's focus stops; on iOS geometry already keeps groups together, so this does
        /// nothing.
        ///
        /// - Returns: The view unchanged.
        public func menuFocusSection() -> some View {
            self
        }

        /// Binds the view's focus to a value of a ``MenuFocusState`` and registers it as a focus stop.
        ///
        /// - Parameters:
        ///   - binding: The focus state's binding.
        ///   - value: The value that means this view has focus.
        /// - Returns: The view as a focus stop.
        public func menuFocusBinding<Value: Hashable>(
            _ binding: MenuFocusState<Value?>.Binding,
            equals value: Value
        ) -> some View {
            modifier(MenuFocusBinding(box: binding.box, focusedValue: value, restingValue: nil))
        }

        /// Binds the view's focus to a Boolean ``MenuFocusState`` and registers it as a focus stop.
        ///
        /// - Parameter binding: The focus state's binding.
        /// - Returns: The view as a focus stop.
        public func menuFocusBinding(_ binding: MenuFocusState<Bool>.Binding) -> some View {
            modifier(MenuFocusBinding(box: binding.box, focusedValue: true, restingValue: false))
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
            onAppear {
                if binding.wrappedValue == nil {
                    binding.wrappedValue = value
                }
            }
        }

        /// Binds the view's focus to a value and marks it as the highlighted menu item while focused.
        ///
        /// - Parameters:
        ///   - binding: The focus state's binding.
        ///   - value: The value that means this view has focus.
        /// - Returns: The view as a focus stop.
        public func menuFocused<Value: Hashable>(
            _ binding: MenuFocusState<Value?>.Binding,
            equals value: Value
        ) -> some View {
            menuFocusBinding(binding, equals: value)
                .environment(\.menuItemFocused, binding.wrappedValue == value)
        }

        /// Binds the view's focus to a Boolean and marks it as the highlighted menu item while focused.
        ///
        /// - Parameter binding: The focus state's binding.
        /// - Returns: The view as a focus stop.
        public func menuFocused(_ binding: MenuFocusState<Bool>.Binding) -> some View {
            menuFocusBinding(binding)
                .environment(\.menuItemFocused, binding.wrappedValue)
        }
    }
#endif
