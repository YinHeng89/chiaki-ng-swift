import SwiftUI

/// How strongly an overlay darkens the content behind it.
public enum Dimming: Sendable {
    /// A light veil behind app modals and confirmation cards.
    case light
    /// The veil behind stream overlays, sign-in panels and Kakusan cards.
    case standard
    /// A heavy veil behind full-screen search and focus overlays.
    case strong

    /// The opacity of the black veil.
    public var opacity: Double {
        switch self {
        case .light:
            0.16
        case .standard:
            0.32
        case .strong:
            0.55
        }
    }

    /// The black veil drawn at this strength.
    public var color: Color {
        Color.black.opacity(opacity)
    }
}
