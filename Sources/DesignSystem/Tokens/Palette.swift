import SwiftUI

/// The colours chiaki-ng uses beyond the system's semantic ones.
///
/// Every lime in the app comes from ``accent``: focus outlines, checked boxes, call-to-action tints and status
/// highlights all share it, so the brand colour has one definition.
public enum Palette {
    /// The lime accent used for focus, selection and calls to action.
    public static let accent = Color(red: 205.0 / 255, green: 220.0 / 255, blue: 40.0 / 255)

    /// The slate blue of the app's ambient motif, used for information and notices over a stream.
    public static let slate = Color(red: 0.16, green: 0.35, blue: 0.48)

    /// The platform's window background colour.
    public static var windowBackground: Color {
        #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
        #else
            return Color(uiColor: .systemBackground)
        #endif
    }

    /// The platform's background colour for controls and grouped content.
    public static var controlBackground: Color {
        #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
        #else
            return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
