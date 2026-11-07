import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

extension CloudGameDetail {
    /// The detail's panel: the layered art detail once its art has loaded, otherwise the card or its loader,
    /// cross-fading between them unless Reduce Motion is on.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The panel for the game's current presentation.
    func detailPanel(_ game: CloudGame) -> some View {
        let shown = store.detail?.shown(for: game.product) ?? .card
        return ZStack {
            if case .layered(let expanded) = shown {
                layeredPanel(game, expanded)
                    .transition(.opacity)
            } else {
                cardPanel(game, loading: shown == .loading)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : AppMotion.animation(reduced: false),
            value: shown.isLayered
        )
    }

    /// The card panel's outer size, its content plus the glass margin.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The size in points.
    func cardSize(_ game: CloudGame) -> CGSize {
        CGSize(width: cardContentWidth(game) + 28, height: detailHeight(game) + 28)
    }

    /// The card detail on a glass panel, or the loading logo alone on the dark page while the layered art
    /// loads, both at the card's size so the layered detail grows from the same place.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - loading: Whether the layered art is still loading.
    /// - Returns: The card panel.
    func cardPanel(_ game: CloudGame, loading: Bool) -> some View {
        ZStack {
            if loading {
                cardLoader(game)
                    .transition(.opacity)
            } else {
                Color.clear
                    .glassPanel(.modal)
                    .shadow(color: .black.opacity(0.38), radius: 30, y: 16)
                details(game)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .frame(width: cardContentWidth(game), height: detailHeight(game), alignment: .top)
                    .foregroundStyle(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(0.14))
                    }
                    .transition(.opacity)
            }
        }
        .id(game.id)
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: GameDetailGrowth.cardFade),
            value: loading
        )
        .frame(width: cardSize(game).width, height: cardSize(game).height)
        .compositingGroup()
    }

    /// The chiaki-ng logo in its connecting animation, with a Close button that holds focus while the layered
    /// art loads.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The loading view.
    func cardLoader(_ game: CloudGame) -> some View {
        ChiakiLogo(size: 96, isConnecting: true)
            .accessibilityLabel(.libraryDetailLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                detailCloseButton
            }
            .clipShape(.rect(cornerRadius: 24))
            .environment(\.menuMove, { _ in focus = .close })
            .menuFocusSection()
            .onAppear {
                focusDetail(game, .close)
            }
            .accessibilityIdentifier("cloud-game-detail-loading")
    }

    /// Frames the layered detail on the dark page with a Close button, rounded corners and a shadow, growing
    /// it from the card's size when it replaces the loader.
    ///
    /// - Parameters:
    ///   - content: The layered detail's scrolling content.
    ///   - start: The size to grow from, or `nil` to appear at full size.
    /// - Returns: The framed detail.
    func detailFrame(_ content: some View, growingFrom start: CGSize?) -> some View {
        content
            .background(Self.detailPage)
            .overlay(alignment: .topTrailing) {
                detailCloseButton
                    .padding(.trailing, closeInset)
            }
            .clipShape(.rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.14))
            }
            .modifier(GameDetailGrowth(start: start, fullHeight: panelHeight))
            .shadow(color: .black.opacity(0.38), radius: 30, y: 16)
            .foregroundStyle(.white)
    }

    /// Focuses a control of the detail, and again if focus is lost before the control takes it.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - target: The control to focus.
    func focusDetail(_ game: CloudGame, _ target: FocusItem?) {
        pendingFocus = target
        focus = target
        guard let target else {
            return
        }
        navigator?.ensureFocus(
            in: { hostWindow },
            reset: {},
            apply: {
                guard focus == nil, store.selectedGame?.id == game.id else {
                    return
                }
                focus = target
            }
        )
    }

    /// Closes the detail.
    func closeDetail() {
        store.send(.closeTapped)
    }

    /// The layered detail's controls in focus order: Close, the game's actions and then each media item.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - presentation: The detail's ratings, media and facts.
    /// - Returns: The controls that can take focus.
    func layeredFocusItems(_ game: CloudGame, _ presentation: GameDetailPresentation) -> [FocusItem] {
        detailFocusItems(game) + presentation.media.indices.map(FocusItem.media)
    }

    /// Moves controller focus through the layered detail.
    ///
    /// While a media item is enlarged, left and right step through the media and any other direction closes
    /// it; otherwise
    /// focus follows the layered detail's focus graph across Close, the actions and the media rail.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - expanded: The loaded layered detail.
    ///   - direction: The direction the controller moved in.
    func moveLayeredDetails(
        _ game: CloudGame, _ expanded: GameDetailFeature.Expanded, direction: MenuMoveDirection
    ) {
        let presentation = GameDetailPresentation(expanded.details)
        if store.detail?.viewed(for: game.product) != nil {
            switch direction {
            case .left:
                store.send(.destination(.presented(.gameDetail(.stepMedia(-1)))))
            case .right:
                store.send(.destination(.presented(.gameDetail(.stepMedia(1)))))
            default:
                store.send(.destination(.presented(.gameDetail(.closeMedia))))
            }
            if let index = store.detail?.viewed(for: game.product) {
                focus = .media(index)
            }
            return
        }
        focus = GameDetailFocusGraph.next(
            from: focus, direction: direction, close: .close,
            actions: detailFocusItems(game).filter { $0 != .close },
            media: presentation.media.indices.map(FocusItem.media)
        )
    }
}

extension CloudGameDetail {
    /// The near-black colour of the layered detail's page, which the stage shading fades into.
    static var detailPage: Color {
        Color(red: 11.0 / 255, green: 13.0 / 255, blue: 18.0 / 255)
    }

    /// The layered detail: the art stage with the title and actions, the ratings, media and facts below it,
    /// and the media viewer over everything.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - expanded: The loaded art and details.
    /// - Returns: The framed, focusable layered detail.
    func layeredPanel(_ game: CloudGame, _ expanded: GameDetailFeature.Expanded) -> some View {
        let presentation = GameDetailPresentation(expanded.details)
        return detailFrame(GameDetailRevealScope {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    layeredSections(
                        game, expanded.layers, presentation,
                        stage: CGSize(width: geometry.size.width, height: stageHeight)
                    )
                }
                .overlay {
                    mediaViewer(game, presentation)
                }
            }
        }, growingFrom: expanded.arrival == .afterLoader
            ? cardSize(game)
            : nil)
            .environment(\.menuMove, { moveDetails(game, direction: $0) })
            .menuFocusSection()
            .onAppear {
                focusLayeredDetails(game, presentation)
            }
            .onChange(of: layeredFocusItems(game, presentation)) { previous, items in
                detailFocusItemsChanged(game, from: previous, to: items)
            }
            .accessibilityIdentifier("cloud-game-detail")
            .id(game.id)
    }

    /// Stacks the art stage and whichever of the rating band, media rail and facts the game has, each
    /// revealed in turn.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - layers: The art drawn on the stage.
    ///   - presentation: The detail's ratings, media and facts.
    ///   - stage: The art stage's size.
    /// - Returns: The scrolling sections.
    func layeredSections(
        _ game: CloudGame, _ layers: GameArtLayers, _ presentation: GameDetailPresentation, stage: CGSize
    ) -> some View {
        let inset = sectionInset(stageWidth: stage.width)
        return VStack(alignment: .leading, spacing: 0) {
            layeredStage(game, layers, size: stage, inset: inset)
            if presentation.showsRatingBand {
                ratingBand(presentation)
                    .padding(.horizontal, inset)
                    .padding(.top, 30)
                    .padding(.bottom, 34)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                    }
                    .gameDetailReveal(.ratings)
            }
            if !presentation.media.isEmpty {
                mediaSection(game, presentation, inset: inset)
                    .padding(.top, 30)
                    .padding(.bottom, 6)
                    .gameDetailReveal(.media)
            }
            if !presentation.facts.isEmpty {
                factsSection(presentation)
                    .padding(.horizontal, inset)
                    .padding(.top, 26)
                    .padding(.bottom, 44)
                    .gameDetailReveal(.details)
            }
        }
        .frame(width: stage.width, alignment: .leading)
    }

    /// Focuses the layered detail when it appears, returning to the control that held focus before when it is
    /// still there and to the initial control otherwise.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - presentation: The detail's ratings, media and facts.
    func focusLayeredDetails(_ game: CloudGame, _ presentation: GameDetailPresentation) {
        let items = layeredFocusItems(game, presentation)
        let held = heldFocus().flatMap { item in
            item != .close && items.contains(item)
                ? item
                : nil
        }
        focusDetail(game, held ?? detailInitialFocus(game))
    }

    /// The art stage: the backdrop, the hero over it, the shading and the title with its metadata and
    /// actions.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - layers: The backdrop, hero and logo art.
    ///   - size: The stage's size.
    ///   - inset: The leading inset of the title block.
    /// - Returns: The stage.
    func layeredStage(_ game: CloudGame, _ layers: GameArtLayers, size: CGSize, inset: CGFloat) -> some View {
        let scale = size.height / 620
        return ZStack(alignment: .bottomLeading) {
            Image(decorative: layers.backdrop, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .offset(y: Self.backdropShift(layers.backdrop, in: size))
                .clipped()
                .gameDetailReveal(.backdrop)
            if let hero = layers.layered?.hero {
                Color.clear
                    .overlay(alignment: .center) {
                        Image(decorative: hero, scale: 1)
                            .resizable()
                            .frame(
                                width: size.height * CGFloat(hero.width) / CGFloat(max(1, hero.height)),
                                height: size.height
                            )
                            .gameDetailReveal(.hero)
                    }
            }
            stageShade
                .gameDetailReveal(.shade)
            stageTitle(game, layers.logo, scale: min(1, size.width / 1280), stageWidth: size.width - inset)
                .padding(.leading, inset)
                .padding(.bottom, 74 * scale)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// How far to push the backdrop down so it shows a little more of its top when it fills the stage.
    ///
    /// - Parameters:
    ///   - image: The backdrop image.
    ///   - size: The stage's size.
    /// - Returns: The vertical offset in points, a tenth of the image's overflow.
    static func backdropShift(_ image: CGImage, in size: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0 else {
            return 0
        }
        let fill = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        return (CGFloat(image.height) * fill - size.height) * 0.1
    }

    /// The shading that darkens the stage's left side and foot into the page so the title and actions stay
    /// legible.
    var stageShade: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Self.detailPage.opacity(0.88), location: 0),
                    .init(color: Self.detailPage.opacity(0.62), location: 0.26),
                    .init(color: Self.detailPage.opacity(0), location: 0.56)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: Self.detailPage, location: 0),
                    .init(color: Self.detailPage.opacity(0.55), location: 0.16),
                    .init(color: Self.detailPage.opacity(0), location: 0.4)
                ],
                startPoint: .bottom, endPoint: .top
            )
        }
        .allowsHitTesting(false)
    }

    /// The stage's title block: the game's logo or name, its metadata and its actions, scaled to the stage's
    /// width.
    ///
    /// On a short compact screen, and for a game in the library that also has a store page, the store button
    /// and its code stand aside on the right, so the title keeps the height above the play button; the Add
    /// to library tile stands aside the same way for a game not yet in the library. Otherwise they follow the
    /// play button in the column.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - logo: The game's logo art, or `nil` to show the name in text.
    ///   - scale: The scale applied to the logo and title block widths.
    ///   - stageWidth: The stage's width after the block's leading inset.
    /// - Returns: The title block.
    @ViewBuilder func stageTitle(
        _ game: CloudGame,
        _ logo: CGImage?,
        scale: CGFloat,
        stageWidth: CGFloat
    ) -> some View {
        if storeStandsAside(game) {
            HStack(alignment: .bottom, spacing: 24) {
                titleColumn(game, logo, scale: scale, aside: true)
                Spacer(minLength: 0)
                storeAside(game)
            }
            .frame(width: max(0, stageWidth - closeInset - 24), alignment: .leading)
        } else {
            titleColumn(game, logo, scale: scale, aside: false)
        }
    }

    /// Whether the store controls stand aside on the right of the stage: on a short compact screen, when a
    /// game in the library also has a store page or code, or when a game waits to be added to the library,
    /// so the column below the title holds only the play or refresh button and its checks.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: Whether the store controls stand aside.
    func storeStandsAside(_ game: CloudGame) -> Bool {
        if cardIsWide {
            return true
        }
        let actions = actions(game)
        guard actions.bundleChoices == nil else {
            return false
        }
        if actions.addToLibrary != nil {
            return true
        }
        return actions.play != nil && (actions.store != nil || actions.purchaseCode != nil)
    }

    /// The store page code with the store link as its footer on one card, or whichever of the two the game
    /// has, on the right of the stage.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The column, empty when the game has neither.
    @ViewBuilder func storeAside(_ game: CloudGame) -> some View {
        let actions = actions(game)
        if actions.bundleChoices == nil, let page = actions.addToLibrary {
            VStack(alignment: .trailing, spacing: 12) {
                libraryAddCard(page, game)
                asideCaption(layout.touch
                    ? .libraryLibraryAddCaptionTouch
                    : .libraryLibraryAddCaptionPhone)
            }
            .gameDetailReveal(.actions)
        } else if actions.bundleChoices == nil, actions.store != nil || actions.purchaseCode != nil {
            VStack(alignment: .trailing, spacing: 12) {
                if let link = actions.store, let code = actions.purchaseCode {
                    storeCodeCard(link, code, game)
                } else if let link = actions.store {
                    storeButton(link, game)
                } else if let code = actions.purchaseCode {
                    purchaseCodeButton(code)
                }
                if actions.purchaseCode != nil {
                    asideCaption(layout.touch
                        ? .libraryStoreCodeCaptionTouch
                        : .libraryStoreCodeCaptionPhone)
                }
            }
            .gameDetailReveal(.actions)
        }
    }

    /// The small caption under an aside tile, right-aligned to the tile.
    ///
    /// - Parameter text: The caption.
    /// - Returns: The caption.
    func asideCaption(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 180, alignment: .trailing)
    }

    /// The logo or name above the metadata and the actions.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - logo: The game's logo art, or `nil` to show the name in text.
    ///   - scale: The scale applied to the logo and title block widths.
    ///   - aside: Whether the store button and code stand aside, so the column leaves them out.
    /// - Returns: The column.
    func titleColumn(_ game: CloudGame, _ logo: CGImage?, scale: CGFloat, aside: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let logo {
                    Image(logo, scale: 1, label: Text(game.name))
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: max(240, 430 * scale),
                            maxHeight: max(120, 220 * scale),
                            alignment: .bottomLeading
                        )
                } else {
                    Text(game.name)
                        .font(.system(size: 32, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: max(240, 430 * scale), alignment: .leading)
                }
            }
            .padding(.bottom, 26)
            .gameDetailReveal(.logo)
            HStack(spacing: 18) {
                metadata(game.platform.uppercased(), icon: .console)
                    .fixedSize()
                metadata(entitlement(game), icon: entitlementIcon(game), highlighted: game.isInCatalog)
                    .fixedSize()
                releaseCountdown(game)
                    .fixedSize()
            }
            .padding(.bottom, 22)
            .gameDetailReveal(.facts)
            VStack(alignment: .leading, spacing: 12) {
                layeredActions(game, aside: aside)
            }
            .gameDetailReveal(.actions)
        }
        .frame(maxWidth: max(300, 470 * scale), alignment: .leading)
    }

    /// The layered detail's actions: the bundle picker, or the play button with the store or add to library
    /// controls, followed by the launch checks, the add hint and the title notice as the game's actions
    /// allow.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - aside: Whether the store button and code stand aside in ``storeAside(_:)``, so they are left out.
    /// - Returns: The stacked actions.
    @ViewBuilder func layeredActions(_ game: CloudGame, aside: Bool) -> some View {
        let actions = actions(game)
        if actions.bundleChoices != nil {
            bundlePicker
                .frame(maxWidth: 420, alignment: .leading)
        } else if layout.isCompact {
            ViewThatFits(in: .horizontal) {
                layeredActionRow(game, actions, aside: aside)
                VStack(alignment: .leading, spacing: layout.controlSpacing) {
                    HStack(spacing: layout.controlSpacing) {
                        layeredActionButtons(game, actions, aside: aside)
                    }
                    if let version = actions.otherVersion {
                        otherVersionButton(version)
                    }
                }
                .fixedSize()
            }
        } else {
            layeredActionRow(game, actions, aside: aside)
        }
        if actions.showsLaunchChecks {
            launchSteps(game)
                .frame(maxWidth: 420, alignment: .leading)
            cardCheckReason(game)
        }
        if let code = actions.purchaseCode, !aside, actions.store == nil {
            purchaseHint(code, owned: actions.play != nil)
        }
        if actions.showsLibraryAddHint, !aside {
            libraryAddHint(actions.addToLibrary)
        }
        if actions.showsTitleNotice {
            titleNotice(game)
        }
    }

    /// The action row at its own size: the action buttons and then the other version's button, which may
    /// run past the title column on a wide stage, where there is room for it.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - actions: What the detail offers for the game.
    ///   - aside: Whether the store button stands aside, so it is left out.
    /// - Returns: The row.
    func layeredActionRow(_ game: CloudGame, _ actions: CloudGameActions, aside: Bool) -> some View {
        HStack(spacing: layout.isCompact
            ? layout.controlSpacing
            : 12) {
                layeredActionButtons(game, actions, aside: aside)
                if let version = actions.otherVersion {
                    otherVersionButton(version)
                }
            }
            .fixedSize()
    }

    /// The buttons of the layered detail's action row, in focus order, before the other version's button.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - actions: What the detail offers for the game.
    ///   - aside: Whether the store button stands aside, so it is left out.
    /// - Returns: The buttons.
    @ViewBuilder func layeredActionButtons(
        _ game: CloudGame,
        _ actions: CloudGameActions,
        aside: Bool
    ) -> some View {
        if let play = actions.play {
            playButton(game, play)
        }
        if let link = actions.store {
            if !aside {
                storeChoice(link, actions.purchaseCode, game)
            }
        } else if actions.addToLibrary != nil {
            if !aside {
                addToLibraryButton(game)
            }
            refreshTitleButton(game)
        }
    }
}

extension CloudGameDetail {
    /// The rating band: the average with its stars and count, the bar for each star rating and the age
    /// rating.
    ///
    /// - Parameter presentation: The detail's ratings.
    /// - Returns: The rating band.
    func ratingBand(_ presentation: GameDetailPresentation) -> some View {
        HStack(alignment: .center, spacing: 40) {
            if let rating = presentation.rating {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(rating.average)
                            .font(.system(size: 46, weight: .semibold))
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(
                                        star <= rating.filledStars
                                            ? Color(red: 1, green: 209.0 / 255, blue: 102.0 / 255)
                                            : .white.opacity(0.22)
                                    )
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Text(rating.count)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
                VStack(spacing: 6) {
                    ForEach(rating.bars) { bar in
                        ratingBar(bar)
                    }
                }
                .frame(maxWidth: 520)
            }
            Spacer(minLength: 0)
            if let age = presentation.age {
                ageRating(age)
            }
        }
        .accessibilityIdentifier("cloud-detail-ratings")
    }

    /// One star rating's share, as a bar with its percentage.
    ///
    /// - Parameter bar: The star rating and its share.
    /// - Returns: The labelled bar.
    func ratingBar(_ bar: GameDetailPresentation.Bar) -> some View {
        HStack(spacing: 12) {
            Text("\(bar.stars)")
                .frame(width: 14, alignment: .leading)
                .foregroundStyle(.white.opacity(0.72))
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.96))
                            .frame(width: geometry.size.width * CGFloat(bar.percent) / 100)
                    }
            }
            .frame(height: 6)
            Text("\(bar.percent)%")
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(.libraryRatingBarAccessibility(stars: bar.stars, percent: bar.percent))
    }

    /// The age rating's icon beside its name and content descriptors.
    ///
    /// - Parameter age: The age rating to show.
    /// - Returns: The age rating block.
    func ageRating(_ age: GameDetailPresentation.Age) -> some View {
        HStack(spacing: 14) {
            if let icon = age.icon {
                GameArtImage(url: icon, size: .icon, contentMode: .fit)
                    .frame(width: 52, height: 62)
                    .clipShape(.rect(cornerRadius: 4))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !age.name.isEmpty {
                    Text(age.name)
                        .font(.system(size: 15, weight: .semibold))
                }
                if let descriptors = age.descriptors {
                    Text(descriptors)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The rail of screenshots and trailers, which enlarges an item when it is pressed and stops scrolling
    /// with the wheel while one is enlarged.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - presentation: The detail's media.
    ///   - inset: The rail's leading and trailing inset.
    /// - Returns: The media rail.
    func mediaSection(_ game: CloudGame, _ presentation: GameDetailPresentation,
                      inset: CGFloat) -> some View {
        GameMediaRail(
            media: presentation.media,
            inset: inset,
            wheelScrolls: store.detail?.viewed(for: game.product) == nil,
            focus: $focus
        ) { index in
            store.send(.destination(.presented(.gameDetail(.viewMedia(index)))))
        }
    }

    /// The spoken label of a media item.
    ///
    /// - Parameters:
    ///   - index: The item's position in the rail.
    ///   - item: The screenshot or trailer.
    /// - Returns: The accessibility label.
    func mediaLabel(_ index: Int, _ item: GameDetailPresentation.Media) -> LocalizedStringResource {
        GameMediaRail.label(index, item)
    }

    /// The enlarged screenshot or playing trailer over a dark scrim, which closes when the scrim is tapped.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - presentation: The detail's media.
    /// - Returns: The viewer, or nothing when no item is enlarged.
    @ViewBuilder func mediaViewer(_ game: CloudGame, _ presentation: GameDetailPresentation) -> some View {
        if let index = store.detail?.viewed(for: game.product), presentation.media.indices.contains(index) {
            ZStack {
                Color.black.opacity(0.88)
                    .contentShape(.rect)
                    .onTapGesture {
                        store.send(.destination(.presented(.gameDetail(.closeMedia))))
                    }
                    .accessibilityLabel(.libraryMediaDismiss)
                switch presentation.media[index] {
                case .screenshot(let url):
                    GameArtImage(url: url, size: .enlarged, contentMode: .fit)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 56)
                        .allowsHitTesting(false)
                        .accessibilityLabel(mediaLabel(index, presentation.media[index]))
                        .accessibilityAddTraits(.isImage)
                        .id(url)
                case .trailer(let url):
                    GameTrailerPlayer(url: url)
                        .aspectRatio(16.0 / 9, contentMode: .fit)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 56)
                        .accessibilityLabel(mediaLabel(index, presentation.media[index]))
                        .id(url)
                }
            }
            .accessibilityIdentifier("cloud-detail-viewer")
            .transition(.opacity)
        }
    }

    /// The game's facts, such as publisher and release date, in labelled columns under a rule.
    ///
    /// - Parameter presentation: The detail's facts.
    /// - Returns: The facts row.
    func factsSection(_ presentation: GameDetailPresentation) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(presentation.facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                        .padding(.bottom, 10)
                    Text(fact.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(fact.value)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("cloud-detail-facts")
    }
}
