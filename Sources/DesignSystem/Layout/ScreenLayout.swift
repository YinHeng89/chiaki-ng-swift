import SwiftUI

/// How much room a screen has, whether it is pointed at by touch and which window chrome it keeps clear of.
///
/// ``ScreenCanvas`` measures it once at the root of a scene and publishes it as
/// ``SwiftUICore/EnvironmentValues/screenLayout``. Views branch on these traits instead of on the platform:
/// an iPad in Split View arranges itself like a phone, a full-screen iPad keeps the regular arrangement with
/// touch-sized controls, and a Mac window shrunk below ``regularSize`` goes compact too.
public struct ScreenLayout: Equatable, Sendable {
    /// How much room the window offers.
    public enum Room: Equatable, Sendable {
        /// Too little for the regular arrangement: a phone, an iPad in Split View or a shrunk window.
        case compact
        /// Enough for the regular arrangement.
        case regular
        /// Room to spare, such as a large window.
        case wide
    }

    /// How much height a screen has, which decides what stacks below the content and what scrolls.
    public enum Stature: Equatable, Sendable {
        /// Too little height for secondary rows, such as a phone in landscape.
        case short
        /// Enough height for secondary rows, such as an iPad in Split View or a full window.
        case tall
    }

    /// The smallest size that still uses the regular arrangement.
    public static let regularSize = CGSize(width: 900, height: 560)

    /// The smallest size that counts as wide.
    public static let wideSize = CGSize(width: 1400, height: 800)

    /// The smallest height that counts as tall.
    public static let tallHeight: CGFloat = 480

    /// The smallest side of a control a finger can hit reliably.
    public static let touchTarget: CGFloat = 44

    /// The padding that keeps content below the window's title bar controls or regular top chrome.
    public static let regularTopChrome: CGFloat = 38

    /// The padding a compact touch screen keeps above its content.
    public static let compactTopChrome: CGFloat = 18

    /// Whether this platform is pointed at by touch.
    public static var touchPlatform: Bool {
        #if os(iOS)
            return true
        #else
            return false
        #endif
    }

    /// Whether this platform draws the window's title bar controls over the content.
    public static var titleBarChrome: Bool {
        #if os(macOS)
            return true
        #else
            return false
        #endif
    }

    /// How much room the window offers.
    public var room: Room

    /// How much height the window offers.
    public var stature: Stature

    /// Whether touch is the primary way to point, so controls need finger-sized targets and no hover.
    public var touch: Bool

    /// The side inset the screen keeps clear, such as a phone's rounded corners or sensor housing.
    public var sideInset: CGFloat

    /// The bottom inset the screen keeps clear, such as the home indicator.
    public var bottomInset: CGFloat

    /// Creates a layout.
    ///
    /// - Parameters:
    ///   - room: How much room the window offers.
    ///   - stature: How much height the window offers.
    ///   - touch: Whether touch is the primary way to point.
    ///   - sideInset: The side inset the screen keeps clear.
    ///   - bottomInset: The bottom inset the screen keeps clear.
    public init(
        room: Room = .regular, stature: Stature = .tall, touch: Bool = Self.touchPlatform,
        sideInset: CGFloat = 0, bottomInset: CGFloat = 0
    ) {
        self.room = room
        self.stature = stature
        self.touch = touch
        self.sideInset = sideInset
        self.bottomInset = bottomInset
    }

    /// The padding that keeps a screen's bottom controls above the home indicator and off the window's edge.
    ///
    /// A compact screen keeps less margin beyond the inset.
    public var bottomChromeInset: CGFloat {
        bottomInset + (
            isCompact
                ? 12
                : 24
        )
    }

    /// Whether screens use their compact arrangement.
    public var isCompact: Bool {
        room == .compact
    }

    /// Whether screens drop their secondary rows and scroll what is left.
    public var isShort: Bool {
        stature == .short
    }

    /// The smallest side of a control: ``touchTarget`` on touch, and no minimum for a pointer.
    public var controlSize: CGFloat {
        touch
            ? Self.touchTarget
            : 0
    }

    /// The margin a sheet or panel keeps from the window's edges, beyond ``sideInset``.
    public var sheetMargin: CGFloat {
        sheetsFillWidth
            ? 16
            : 20
    }

    /// The gap between neighbouring controls, wider on touch so fingers do not straddle two.
    public var controlSpacing: CGFloat {
        touch
            ? 12
            : 8
    }

    /// Whether affordances may wait for a hover, such as a rail that widens or arrows that appear under the
    /// pointer. On touch they must be visible or answer a tap instead.
    public var hoverAffordances: Bool {
        !touch
    }

    /// Whether sheets and panels span the window instead of floating at a fixed width.
    public var sheetsFillWidth: Bool {
        isCompact
    }

    /// Whether a screen sets its two halves side by side: anywhere but a tall, narrow window such as a phone held
    /// upright.
    public var sideBySide: Bool {
        !isCompact || isShort
    }

    /// The padding that keeps a screen's content below the window's top chrome.
    ///
    /// A title bar's controls always need the regular padding. Without one, a compact screen keeps less.
    public var topChromeInset: CGFloat {
        if Self.titleBarChrome || !isCompact {
            return Self.regularTopChrome
        }
        return Self.compactTopChrome
    }

    /// Classifies a window size.
    ///
    /// - Parameter size: The space available to the scene.
    /// - Returns: ``Room/compact`` below ``regularSize`` on either axis, ``Room/wide`` at or above
    ///   ``wideSize`` on both, and ``Room/regular`` between.
    public static func room(for size: CGSize) -> Room {
        if size.width < regularSize.width || size.height < regularSize.height {
            return .compact
        }
        if size.width >= wideSize.width && size.height >= wideSize.height {
            return .wide
        }
        return .regular
    }

    /// Classifies a window height.
    ///
    /// - Parameter size: The space available to the scene.
    /// - Returns: ``Stature/short`` below ``tallHeight``, ``Stature/tall`` otherwise.
    public static func stature(for size: CGSize) -> Stature {
        size.height < tallHeight
            ? .short
            : .tall
    }

    /// Measures the layout of a scene.
    ///
    /// - Parameters:
    ///   - size: The space available to the scene.
    ///   - safeArea: The scene's safe area insets.
    /// - Returns: The layout for this platform in that space.
    public static func measured(size: CGSize, safeArea: EdgeInsets) -> ScreenLayout {
        ScreenLayout(
            room: room(for: size),
            stature: stature(for: size),
            touch: touchPlatform,
            sideInset: max(safeArea.leading, safeArea.trailing),
            bottomInset: safeArea.bottom
        )
    }
}

extension EnvironmentValues {
    /// The layout traits of the scene, published by ``SwiftUICore/View/screenLayout()``.
    @Entry public var screenLayout = ScreenLayout()

    /// Whether the window is too small for the regular layout, so screens use their compact arrangement.
    ///
    /// Reads and writes ``ScreenLayout/room`` on ``screenLayout``.
    public var compactScreen: Bool {
        get {
            screenLayout.isCompact
        }
        set {
            screenLayout.room = newValue
                ? .compact
                : .regular
        }
    }

    /// The extra side inset a compact screen keeps clear, such as a phone's rounded corners or sensor housing.
    ///
    /// Reads and writes ``ScreenLayout/sideInset`` on ``screenLayout``.
    public var screenSideInset: CGFloat {
        get {
            screenLayout.sideInset
        }
        set {
            screenLayout.sideInset = newValue
        }
    }
}
