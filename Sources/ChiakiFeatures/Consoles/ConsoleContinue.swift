import ChiakiModels
import Foundation
import SwiftUI

/// How a console card shows its last played title, chosen by console and card width.
enum ConsoleContinueForm: Equatable {
    /// The card shows no last played title.
    case hidden
    /// The card shows the smaller continue button.
    case compact
    /// The card shows the wide continue button.
    case wide

    /// The card width from which a card shows its last played title.
    static let compactWidth: CGFloat = 660

    /// The form of a card.
    ///
    /// - Parameters:
    ///   - kind: The console generation; only PS5 cards show a last played title.
    ///   - lastPlayed: The last played title, if any.
    ///   - cardWidth: The card's width.
    /// - Returns: Hidden for a PS4, without a title or below ``compactWidth``; wide from
    ///   ``ConsoleCard/wideWidth``;
    ///   compact otherwise.
    static func of(
        kind: RegistrationFlow.ConsoleKind, lastPlayed: RecentTitle?, cardWidth: CGFloat
    ) -> ConsoleContinueForm {
        guard kind == .ps5, lastPlayed != nil, cardWidth >= compactWidth else {
            return .hidden
        }
        return cardWidth >= ConsoleCard.wideWidth
            ? .wide
            : .compact
    }

    /// The share of the card's width the layered continue art covers.
    var artFraction: CGFloat {
        switch self {
        case .hidden:
            0
        case .compact, .wide:
            1
        }
    }
}

/// The geometry of the layered continue art on a console card.
enum ConsoleContinueLayout {
    /// Where the hero figure's centre sits across the art, as a fraction of its width.
    static let heroCentre: CGFloat = 0.64
    /// The height of the hero figure, as a fraction of the art's height.
    static let figureHeight: CGFloat = 0.9
    /// Where the hero figure's middle sits down the art, as a fraction of its height.
    static let figureMiddle: CGFloat = 0.54
    /// The art width beyond which extra room shifts the hero and widens the title inset.
    static let roomyWidth: CGFloat = 900

    /// The art width beyond ``roomyWidth``.
    ///
    /// - Parameter width: The art's width.
    /// - Returns: The extra width, or zero.
    static func spare(_ width: CGFloat) -> CGFloat {
        max(0, width - roomyWidth)
    }

    /// The trailing inset of the logo and pill, growing with the spare width.
    ///
    /// - Parameter width: The art's width.
    /// - Returns: The inset in points.
    static func titleInset(_ width: CGFloat) -> CGFloat {
        26 + spare(width) * 0.07
    }
    /// The animation that lifts the art while it is hovered or focused.
    static let lift = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.5)

    /// Where to draw the hero layer so its figure fills the set height, centred at the set point.
    ///
    /// - Parameters:
    ///   - hero: The hero layer.
    ///   - figure: The bounds of the figure within the hero layer, as unit fractions.
    ///   - size: The art's size.
    /// - Returns: The frame of the whole hero layer.
    static func heroFrame(_ hero: CGImage, figure: CGRect, in size: CGSize) -> CGRect {
        let height = size.height * figureHeight / max(figure.height, 0.05)
        let width = height * CGFloat(hero.width) / CGFloat(max(1, hero.height))
        let centre = size.width * heroCentre - spare(size.width) * 0.2
        return CGRect(
            x: centre - width * figure.midX, y: size.height * figureMiddle - height * figure.midY,
            width: width,
            height: height
        )
    }
}

/// What a card's continue area shows.
enum ConsoleContinueFace: Equatable {
    /// The card shows no last played title.
    case none
    /// The card shows the title's plain tile.
    case tile
    /// The card shows the title's layered key art.
    case art(GameArtLayers)

    /// The layered art, when the face shows it.
    var layers: GameArtLayers? {
        guard case .art(let layers) = self else {
            return nil
        }
        return layers
    }
}

/// Decides, for every card of the console grid, whether and how it shows its last played title, and which
/// art to fetch.
struct ConsoleContinuePlan {
    /// The cards of the grid.
    let consoles: [DisplayedConsole]
    /// The recently played titles of each console, once loaded.
    let recentlyPlayed: RecentlyPlayedReducer.State?
    /// The width of the grid.
    let gridWidth: CGFloat
    /// Whether layered key art is drawn; otherwise cards show plain tiles.
    var layeredArt = true

    /// The number of grid columns at the grid's width.
    var columns: Int {
        ConsoleGridLayout.columns(for: gridWidth, cards: consoles.count)
    }

    /// The width of one card at the grid's column count.
    var cardWidth: CGFloat {
        let columns = CGFloat(columns)
        return (gridWidth - ConsoleGridLayout().spacing * (columns - 1)) / columns
    }

    /// The last played title of a card.
    ///
    /// - Parameter item: The card.
    /// - Returns: The preview's sample title, or the first recently played title of the console.
    func title(for item: DisplayedConsole) -> RecentTitle? {
        if item.preview {
            return item.sampleTitle
        }
        guard let id = item.target.id else {
            return nil
        }
        return recentlyPlayed?.rail(for: id)?.titles.first
    }

    /// How a card shows its last played title.
    ///
    /// - Parameter item: The card.
    /// - Returns: The form at the grid's card width.
    func form(for item: DisplayedConsole) -> ConsoleContinueForm {
        ConsoleContinueForm.of(kind: item.target.kind, lastPlayed: title(for: item), cardWidth: cardWidth)
    }

    /// Whether a card shows its last played title.
    ///
    /// - Parameter item: The card.
    /// - Returns: `true` unless the form is hidden.
    func shows(_ item: DisplayedConsole) -> Bool {
        form(for: item) != .hidden
    }

    /// The ids of the paired consoles whose cards show their last played title.
    var continuing: Set<UUID> {
        Set(consoles.filter { !$0.preview && shows($0) }.compactMap(\.target.id))
    }

    /// What a card's continue area shows.
    ///
    /// - Parameters:
    ///   - item: The card.
    ///   - art: The fetched layered art.
    ///   - samples: The studio that draws a preview card's sample art.
    /// - Returns: Nothing when the card shows no title, the layered art once fetched, or the plain tile
    ///   otherwise.
    func face(
        for item: DisplayedConsole,
        art: ConsoleArtReducer.State?,
        samples: SampleArtStudio
    ) -> ConsoleContinueFace {
        guard shows(item), let title = title(for: item) else {
            return .none
        }
        guard layeredArt else {
            return .tile
        }
        let layers = item.preview
            ? sampleLayers(item, title, samples: samples)
            : art?.layers(for: title.conceptID)
        return layers.map(ConsoleContinueFace.art) ?? .tile
    }

    private func sampleLayers(
        _ item: DisplayedConsole,
        _ title: RecentTitle,
        samples: SampleArtStudio
    ) -> GameArtLayers? {
        item.sampleRecentlyPlayed == .withLayeredArt
            ? samples.layers(named: title.name)
            : nil
    }

    /// The layered art to fetch for the cards that show a last played title, visible cards first.
    ///
    /// - Parameters:
    ///   - account: The account to fetch the art as.
    ///   - visible: The ids of the consoles whose cards are on screen.
    /// - Returns: The requests, or none when layered art is off or no account is selected.
    func artRequests(account: UUID?, visible: Set<UUID>) -> [ConsoleArtRequest] {
        guard layeredArt, let account else {
            return []
        }
        let asking = consoles.compactMap { item -> (console: UUID, request: ConsoleArtRequest)? in
            guard !item.preview, shows(item), let id = item.target.id, let title = title(for: item),
                  !title.conceptID.isEmpty else {
                return nil
            }
            return (id, ConsoleArtRequest(accountID: account, conceptID: title.conceptID))
        }
        return (asking.filter { visible.contains($0.console) } + asking
            .filter { !visible.contains($0.console) })
            .map(\.request)
    }
}

/// The layered key art of a card's last played title: backdrop, hero and logo, lifted while hovered or
/// focused,
/// with a pill under the logo; tapping the right half relaunches the title.
struct ConsoleContinueArt<Pill: View>: View {
    /// The title's background, hero and logo layers.
    let layers: GameArtLayers.Layered
    /// Whether the art is laid out for a wide card, which enlarges the logo.
    let wide: Bool
    /// Whether the card's continue stop holds focus, which lifts the art.
    let focused: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artContentBounds) private var contentBounds

    private var lifted: Bool {
        hovered || focused
    }

    /// Relaunches the title.
    let resume: () -> Void
    /// The control drawn under the logo.
    @ViewBuilder let pill: Pill

    var body: some View {
        GeometryReader { proxy in
            GameDetailRevealScope {
                stage(proxy.size)
            }
        }
        .onHover {
            hovered = $0
        }
    }

    private func stage(_ size: CGSize) -> some View {
        let hero = ConsoleContinueLayout.heroFrame(
            layers.hero, figure: contentBounds.box(of: layers.hero), in: size
        )
        return ZStack(alignment: .trailing) {
            ZStack {
                Image(decorative: layers.background, scale: 1)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .offset(y: CloudGameDetail.backdropShift(layers.background, in: size))
                    .scaleEffect(lifted
                        ? 1.05
                        : 1)
                        .gameDetailReveal(.backdrop)
                ScaledArt(image: layers.hero, size: hero.size)
                    .position(x: hero.midX, y: hero.midY)
                    .scaleEffect(lifted
                        ? 1.08
                        : 1)
                        .gameDetailReveal(.hero)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0), location: 0.52)
                    ],
                    startPoint: .bottom, endPoint: .top
                )
                .gameDetailReveal(.shade)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0),
                        .init(color: .black.opacity(0.32), location: 0.38),
                        .init(color: .black.opacity(0), location: 0.62)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .gameDetailReveal(.shade)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(
                Rectangle()
                    .size(width: size.width / 2, height: size.height)
                    .offset(x: size.width / 2)
            )
            .onTapGesture(perform: resume)
            .accessibilityHidden(true)
            .animation(reduceMotion
                ? nil
                : ConsoleContinueLayout.lift, value: lifted)
            titleBlock
                .padding(.trailing, ConsoleContinueLayout.titleInset(size.width))
                .offset(y: 10)
                .gameDetailReveal(.logo)
        }
        .frame(width: size.width, height: size.height)
    }

    private var titleBlock: some View {
        VStack(alignment: .trailing, spacing: 16) {
            ScaledArt(
                image: layers.logo,
                size: ScaledArtCache.fitted(
                    layers.logo,
                    in: wide
                        ? CGSize(width: 230, height: 76)
                        : CGSize(width: 170, height: 60)
                )
            )
            .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
            .allowsHitTesting(false)
            pill
        }
    }
}
