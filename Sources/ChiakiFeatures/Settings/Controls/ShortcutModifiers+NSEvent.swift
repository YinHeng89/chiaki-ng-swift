import ChiakiModels
import PlatformUI
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

#if os(macOS)
    extension ShortcutModifiers {
        /// Creates the shortcut modifier set matching the Control, Option, Shift and Command keys held in an
        /// AppKit event.
        /// - Parameter flags: The modifier flags from an `NSEvent`.
        public init(_ flags: NSEvent.ModifierFlags) {
            var modifiers: ShortcutModifiers = []
            if flags.contains(.control) {
                modifiers.insert(.control)
            }
            if flags.contains(.option) {
                modifiers.insert(.option)
            }
            if flags.contains(.shift) {
                modifiers.insert(.shift)
            }
            if flags.contains(.command) {
                modifiers.insert(.command)
            }
            self = modifiers
        }
    }
#endif
