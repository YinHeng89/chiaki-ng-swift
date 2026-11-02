import Observation
import SwiftUI

#if os(macOS)
    /// The focus state of a menu: SwiftUI's `FocusState` on macOS.
    ///
    /// Views declare `@MenuFocusState` and bind it with ``SwiftUICore/View/menuFocused(_:equals:)`` so the same
    /// code drives AppKit focus on macOS and the touch navigator's focus stops on iOS.
    public typealias MenuFocusState = FocusState
#else
    /// The focus state of a menu on iOS, where SwiftUI's `FocusState` cannot focus controls without a
    /// hardware keyboard.
    ///
    /// The touch navigator moves focus by writing the bound value of the stop it chose.
    @MainActor
    @propertyWrapper
    public struct MenuFocusState<Value: Hashable>: DynamicProperty {
        /// A binding to a ``MenuFocusState``, passed to ``SwiftUI/View/menuFocused(_:equals:)``.
        @MainActor
        @propertyWrapper
        public struct Binding {
            /// The shared box the state and the focus stop read and write.
            let box: MenuFocusBox<Value>

            /// The focused value.
            public var wrappedValue: Value {
                get {
                    box.value
                }
                nonmutating set {
                    box.value = newValue
                }
            }

            /// The binding itself.
            public var projectedValue: Binding {
                self
            }
        }

        @State private var box: MenuFocusBox<Value>

        /// Creates a Boolean focus state that starts unfocused.
        public init() where Value == Bool {
            _box = State(initialValue: MenuFocusBox(false))
        }

        /// Creates an optional focus state that starts with nothing focused.
        public init<Wrapped: Hashable>() where Value == Wrapped? {
            _box = State(initialValue: MenuFocusBox(nil))
        }

        /// The focused value.
        public var wrappedValue: Value {
            get {
                box.value
            }
            nonmutating set {
                box.value = newValue
            }
        }

        /// A binding to the focus state.
        public var projectedValue: Binding {
            Binding(box: box)
        }
    }
#endif
