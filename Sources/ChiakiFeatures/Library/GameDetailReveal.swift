import ChiakiModels
import SwiftUI

/// The staged entrance of the layered game detail: each part fades, scales and slides in on its own curve and
/// delay.
public enum GameDetailRevealStep {
    /// The parts of the detail, from the backdrop art through the logo and facts to the media and details
    /// sections.
    case backdrop, hero, shade, logo, facts, actions, ratings, media, details

    /// The animation curve the part enters with.
    public var curve: Animation {
        switch self {
        case .backdrop:
            .timingCurve(0.2, 0.7, 0.2, 1, duration: 1.6)
        case .hero:
            .timingCurve(0.16, 0.8, 0.24, 1, duration: 1.3)
        case .shade:
            .easeOut(duration: 1.2)
        case .logo:
            .timingCurve(0.2, 0.7, 0.2, 1, duration: 1.1)
        case .facts, .actions:
            .easeOut(duration: 0.7)
        case .ratings, .media, .details:
            .easeOut(duration: 0.8)
        }
    }

    /// How many seconds after the reveal starts the part begins to enter.
    public var delay: Double {
        switch self {
        case .backdrop, .shade:
            0
        case .hero:
            0.35
        case .logo:
            0.95
        case .facts:
            1.45
        case .actions:
            1.6
        case .ratings:
            1.8
        case .media:
            2
        case .details:
            2.15
        }
    }

    /// The scale the part starts from before it enters; backdrop art starts slightly zoomed in.
    public var hiddenScale: CGFloat {
        switch self {
        case .backdrop, .shade:
            1.08
        case .logo:
            0.96
        case .hero, .facts, .actions, .ratings, .media, .details:
            1
        }
    }

    /// How far the part starts below its resting position before it enters.
    public var hiddenOffset: CGSize {
        switch self {
        case .backdrop, .shade, .hero:
            .zero
        case .logo:
            CGSize(width: 0, height: 14)
        case .facts, .actions, .ratings, .media, .details:
            CGSize(width: 0, height: 22)
        }
    }

    /// The blur the part starts with before it enters; only the logo is blurred.
    public var hiddenBlur: CGFloat {
        self == .logo
            ? 8
            : 0
    }
}

extension EnvironmentValues {
    /// Whether the staged parts of the game detail have entered; true outside a reveal scope.
    @Entry public var gameDetailRevealed = true
    /// Extra seconds added to every reveal delay, such as the time the panel spends growing first.
    @Entry public var gameDetailRevealDelay: Double = 0
}

/// Starts the staged reveal of the game detail parts inside it the moment it appears.
public struct GameDetailRevealScope<Content: View>: View {
    /// The detail content whose parts are revealed.
    public let content: Content
    @State private var revealed = false

    /// Creates a scope around the detail content.
    ///
    /// - Parameter content: The detail content whose parts are revealed.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .environment(\.gameDetailRevealed, revealed)
            .onAppear {
                revealed = true
            }
    }
}

private struct GameDetailReveal: ViewModifier {
    let step: GameDetailRevealStep
    @Environment(\.gameDetailRevealed) private var revealed
    @Environment(\.gameDetailRevealDelay) private var lead
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool {
        revealed || reduceMotion
    }

    func body(content: Content) -> some View {
        sharpened(content)
            .opacity(shown
                ? 1
                : 0)
                .scaleEffect(shown
                    ? 1
                    : step.hiddenScale)
                    .offset(shown
                        ? .zero
                        : step.hiddenOffset)
                        .animation(
                            reduceMotion
                                ? nil
                                : step.curve.delay(step.delay + lead),
                            value: revealed
                        )
    }

    @ViewBuilder private func sharpened(_ content: Content) -> some View {
        if step.hiddenBlur > 0 {
            content.blur(radius: shown
                ? 0
                : step.hiddenBlur)
        } else {
            content
        }
    }
}

extension View {
    /// Hides the view until the enclosing reveal scope starts, then brings it in with the step's animation.
    ///
    /// With Reduce Motion on, the view shows at once.
    ///
    /// - Parameter step: Which part of the detail the view is.
    public func gameDetailReveal(_ step: GameDetailRevealStep) -> some View {
        modifier(GameDetailReveal(step: step))
    }
}

/// Grows the detail panel's rounded mask from the tapped card's size to full size, and delays the staged
/// reveal until it has grown.
///
/// Without a starting size, or with Reduce Motion on, the panel appears at full size.
public struct GameDetailGrowth: ViewModifier {
    /// How long the panel takes to grow, in seconds.
    public nonisolated static let duration = 0.4
    /// How long the card cross-fades between its loading and loaded content, in seconds.
    public nonisolated static let cardFade = 0.25

    /// The size of the card the panel grows from, or `nil` to start at full size.
    public let start: CGSize?
    /// The panel's full height.
    public let fullHeight: CGFloat
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a game detail growth.
    ///
    /// - Parameters:
    ///   - start: The size of the card the panel grows from, or `nil` to start at full size.
    ///   - fullHeight: The panel's full height.
    public init(start: CGSize?, fullHeight: CGFloat) {
        self.start = start
        self.fullHeight = fullHeight
    }

    private var grows: Bool {
        start != nil && !reduceMotion
    }

    private var full: Bool {
        grown || !grows
    }

    /// Masks the content to the growing panel and pushes back the reveal by the growth time.
    public func body(content: Content) -> some View {
        content
            .environment(\.gameDetailRevealDelay, grows
                ? Self.duration
                : 0)
                .frame(maxWidth: 1280)
                .frame(height: fullHeight)
                .mask {
                    RoundedRectangle(cornerRadius: 26)
                        .frame(
                            width: full
                                ? nil
                                : start?.width,
                            height: full
                                ? nil
                                : start?.height
                        )
                        .animation(
                            grows
                                ? .smooth(duration: Self.duration, extraBounce: 0)
                                : nil,
                            value: grown
                        )
                }
                .onAppear {
                    grown = true
                }
    }
}
