import SwiftUI

/// The colouring of the logo artwork for the current appearance.
enum ChiakiLogoInk: Hashable {
    /// The original artwork with its navy face, used on light backgrounds.
    case navy

    /// The artwork with its signal waves removed and its navy parts outlined in lime, used on dark backgrounds.
    case outlined

    /// Chooses the ink that stays legible in a colour scheme.
    ///
    /// - Parameter scheme: The colour scheme the logo is shown in.
    init(_ scheme: ColorScheme) {
        self = scheme == .dark
            ? .outlined
            : .navy
    }
}
