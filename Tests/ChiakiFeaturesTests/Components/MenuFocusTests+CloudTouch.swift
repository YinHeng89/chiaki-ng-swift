import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI
import Testing

extension MenuFocusTests {
    private static let concept = "https://store.playstation.com/en-gb/concept/1"

    private nonisolated static let layeredArt = GameDetails.LayeredArt(
        background: "https://image.api.playstation.com/background.png",
        hero: "https://image.api.playstation.com/hero.png",
        logo: "https://image.api.playstation.com/logo.png"
    )

    private static func pixel() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let image = context?.makeImage() else {
            fatalError("no bitmap context")
        }
        return image
    }

    private func cloudStore(
        _ games: [CloudGame], filter: CloudLibraryFilter = .all, layered: Bool = false
    ) -> StoreOf<CloudLibraryFeature> {
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: games)
        state.phase = .ready
        state.filter = filter
        let layers = layered
            ? GameArtLayers(background: Self.pixel(), hero: Self.pixel(), logo: Self.pixel())
            : nil
        return Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
            $0.catalog.gameDetails = { _, _ in
                layered
                    ? .success(GameDetails(layeredArt: Self.layeredArt))
                    : .failure(CatalogFailure(reason: .coreClosed))
            }
            $0.catalog.artLayers = { _ in layers }
            $0.catalog.heldArtLayers = { _ in layers }
            $0.catalog.storefrontCheck = CatalogClient.unanswered
            $0.cloud.loadDatacenters = {
                CloudDatacenterSettings().selectingAtLaunch(false)
            }
        }
    }

    private func ownedGames(_ count: Int) -> [CloudGame] {
        (0..<count).map { index in
            CloudGame(
                productId: "game-\(index)", name: "Game \(index)", platform: "PS5", isOwned: true,
                standing: .inLibrary
            )
        }
    }

    @Test func anOwnedGameWithAStorePageShowsItsCodeTileBesideTheTitle() async {
        let owned = CloudGame(
            productId: "owned", name: "Owned", platform: "PS5", isOwned: true, conceptUrl: Self.concept,
            standing: .inLibrary
        )
        let store = cloudStore([owned] + ownedGames(3), layered: true)
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .game("owned")
        }
        await harness.send(.confirm)
        await harness.pause(900)
        #expect(store.selectedGame?.id == "owned")
        var walked = [store.heldFocus]
        for _ in 0..<5 {
            await harness.send(.right)
            await harness.pause(150)
            walked.append(store.heldFocus)
        }
        #expect(walked.contains(.store), "\(walked)")
        #expect(!walked.contains(.purchaseCode), "\(walked)")
    }

    @Test func aGameToAddShowsItsAddToLibraryTileBesideTheTitle() async {
        let waiting = CloudGame(
            productId: "waiting", name: "Waiting", platform: "PS5", plusCatalog: true,
            conceptUrl: Self.concept,
            needsLibraryAdd: true, canBeAddedToLibrary: true
        )
        let store = cloudStore([waiting] + ownedGames(3), filter: .plus, layered: true)
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .game("waiting")
        }
        await harness.send(.confirm)
        await harness.pause(900)
        #expect(store.selectedGame?.id == "waiting")
        var walked = [store.heldFocus]
        for _ in 0..<5 {
            await harness.send(.right)
            await harness.pause(150)
            walked.append(store.heldFocus)
        }
        #expect(walked.contains(.addToLibrary), "\(walked)")
    }

    @Test func aStoreGameShowsItsCodeTileAsTheStoreStop() async {
        let sale = CloudGame(
            productId: "sale", name: "Sale", platform: "PS5", conceptUrl: Self.concept, standing: .store
        )
        let store = cloudStore(ownedGames(4) + [sale], filter: .browse)
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .game("sale")
        }
        await harness.pause(300)
        #expect(store.heldFocus == .game("sale"))
        await harness.send(.confirm)
        await harness.pause(600)
        #expect(store.selectedGame?.id == "sale")
        await harness.pause(300)
        var walked = [store.heldFocus]
        var tile = CGRect.zero
        for _ in 0..<4 {
            await harness.send(.right)
            await harness.pause(150)
            walked.append(store.heldFocus)
            if store.heldFocus == .store {
                tile = harness.focusedFrame
            }
        }
        #expect(walked.contains(.store), "\(walked)")
        #expect(!walked.contains(.purchaseCode), "\(walked)")
        #expect(walked.contains(.close), "\(walked)")
        #expect(tile.width >= 120 && tile.height >= 120, "\(tile)")
    }

    @Test func aTallCompactCloudLibraryFitsAGridAndTurnsPagesFromItsDotStrip() async {
        let store = cloudStore(ownedGames(24))
        let harness = MenuFocusHarness(width: 420, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 800)
                .environment(\.screenLayout, ScreenLayout(room: .compact, stature: .tall, touch: true)))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        #expect(store.gridShape.rows > 1, "\(store.gridShape)")
        #expect(store.pageCount > 1)
        #expect(store.page == 0)
        await harness.send([.down, .down])
        await harness.pause(200)
        #expect(store.heldFocus != .pageBar)
        if case .game = store.heldFocus {
        } else {
            Issue.record("focus left the games for \(String(describing: store.heldFocus))")
        }
        let dots = CloudPageDots.dots(page: 0, count: store.pageCount)
        let stride = CloudPageDotStrip.dot + CloudPageDotStrip.gap
        let origin = (420 - CGFloat(dots.count) * stride) / 2 + stride / 2
        let last = dots.count - 1
        click(
            CGPoint(x: origin + CGFloat(last) * stride, y: 32 - CloudGameGrid.dotStripDrop),
            in: harness.window
        )
        await waitUntil(harness) {
            store.page == dots[last].page
        }
        #expect(store.page == dots[last].page)
        click(CGPoint(x: origin, y: 32 - CloudGameGrid.dotStripDrop), in: harness.window)
        await waitUntil(harness) {
            store.page == 0
        }
        #expect(store.page == 0)
    }

    @Test func aShortCompactCloudLibraryKeepsOneRow() async {
        let store = cloudStore(ownedGames(24))
        let harness = MenuFocusHarness(width: 850, height: 390) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 390)
                .environment(
                    \.screenLayout,
                    ScreenLayout(room: .compact, stature: .short, touch: true, sideInset: 59)
                ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        #expect(store.gridShape.rows == 1, "\(store.gridShape)")
        #expect(store.pageCount > 1)
    }

    @Test func touchPageArrowsAreOnShowWithoutAPointer() {
        let touch = ScreenLayout(room: .regular, stature: .tall, touch: true)
        let pointer = ScreenLayout(room: .regular, stature: .tall, touch: false)
        #expect(CloudGameGrid.showsArrows(
            layout: touch, pointerOver: false, pageCount: 3, empty: false, loading: false
        ))
        #expect(!CloudGameGrid.showsArrows(
            layout: pointer, pointerOver: false, pageCount: 3, empty: false, loading: false
        ))
        #expect(CloudGameGrid.showsArrows(
            layout: pointer, pointerOver: true, pageCount: 3, empty: false, loading: false
        ))
        #expect(!CloudGameGrid.showsArrows(
            layout: touch, pointerOver: true, pageCount: 1, empty: false, loading: false
        ))
        #expect(!CloudGameGrid.showsArrows(
            layout: touch, pointerOver: true, pageCount: 3, empty: true, loading: false
        ))
        #expect(!CloudGameGrid.showsArrows(
            layout: touch, pointerOver: true, pageCount: 3, empty: false, loading: true
        ))
    }
}
